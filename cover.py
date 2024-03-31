#!/usr/bin/env python3

""" Cover controller script. """

from gpiozero import LED, Button
from systemd.journal import JournalHandler
from typing import List
from typing import Optional
from typing import Tuple
import argparse
import functools
import logging
import logging.handlers
import paho.mqtt.client as mqtt
import posixpath
import queue
import ssl
import sys
import time

logger = logging.getLogger(__name__)

PAYLOAD_UP: str = "OPEN"
PAYLOAD_DOWN: str = "CLOSE"
PAYLOAD_STOP: str = "STOP"

STATE_CLOSED: str = "closed"
STATE_CLOSING: str = "closing"
STATE_ERROR: str = "error"
STATE_INITIAL: str = "initial"
STATE_OPEN: str = "open"
STATE_OPENING: str = "opening"
STATE_PARTIAL: str = "partial"


class Cover:
    """
    Represents a single cover.

    One cover is a shade that has a motor with an H-bridge, with two GPIOs
    outputs connected to the H-bridge and two GPIO inputs connected to switches
    that indicate the limits.

    Each motor attached to the cover has three states:

        * Opening
        * Closing
        * Stopped

    From these motor states and the switches each cover derives several more
    states:

        * Open
        * Closed
        * Opening
            * if top switch is set -> Open
            * if state is Opening for more than 70s -> Error
            * if both switches are set -> Error
        * Unknown
            * if top switch is set -> Open
            * if bottom switch is set -> Closed
            * if both switches are set -> Error
        * Error
    """

    class _LoggerAdapter(logging.LoggerAdapter):
        """Prepends the context onto logging messages."""

        def process(self, msg: str, kwargs: dict) -> Tuple[str, dict]:
            return f"[{self.extra['base_topic']}] {msg}", kwargs

    def __init__(
        self,
        *,
        up_motor_pin: int,
        down_motor_pin: int,
        up_limit_pin: int,
        down_limit_pin: int,
        up_time_limit: float,
        down_time_limit: float,
        base_topic: str,
        client: mqtt.Client,
    ):
        self.logger = self._LoggerAdapter(
            logger=logging.getLogger(__name__),
            extra={"base_topic": base_topic},
        )

        self.up_motor = LED(up_motor_pin)
        self.down_motor = LED(down_motor_pin)
        self.lower_limit = Button(down_limit_pin)
        self.upper_limit = Button(up_limit_pin)
        self.down_time_limit = down_time_limit
        self.up_time_limit = up_time_limit
        self.set_topic = posixpath.join(base_topic, "set")
        self.position_topic = posixpath.join(base_topic, "position")

        self.client = client
        self.queue = queue.Queue()
        self._state_start = time.monotonic()
        self._state: str = STATE_INITIAL
        self._postion: Optional[float] = None

        self.motor_stop()

    def get_state(self) -> str:
        """Get the current cover state."""
        return self._state

    def state_elapsed(self) -> float:
        """Get the duration in seconds of the current state."""
        return time.monotonic() - self._state_start

    def set_state(self, state: str):
        """Set the current cover state."""
        elapsed = self.state_elapsed()
        self.logger.debug(
            f"Changing state from {self._state} to {state} "
            f"after {elapsed:.3f}s"
        )

        if self._state == STATE_OPENING:
            self.up_motor.off()
            self.down_motor.on()
            time.sleep(0.12)
            self.down_motor.off()
        elif self._state == STATE_CLOSING:
            self.down_motor.off()
            self.up_motor.on()
            time.sleep(0.12)
            self.up_motor.off()

        if (
            state not in {STATE_OPEN, STATE_CLOSED}
            and self._postion is not None
        ):
            if self._state == STATE_OPENING:
                self._postion += elapsed * (100 / self.up_time_limit)
                self._postion = min(self._postion, 99)
            elif self._state == STATE_CLOSING:
                self._postion -= elapsed * (100 / self.down_time_limit)
                self._postion = max(self._postion, 1)

            self.publish_position()

        self._state = state
        self._state_start = time.monotonic()

    def publish_position(self):
        if self._postion is not None:
            p = str(int(self._postion))
            self.logger.debug(f"publishing {p}")
            self.client.publish(self.position_topic, p)

    def get_payload(self) -> Optional[str]:
        """Gets a payload from the queue if avaliable."""
        try:
            payload = self.queue.get_nowait()
        except queue.Empty:
            return None
        else:
            self.logger.debug(f"new payload: {payload}")
            return payload

    def state_closing(self):
        if self.lower_limit.is_pressed:
            self.set_state(STATE_CLOSED)
            return

        self.up_motor.off()
        self.down_motor.on()

        elapsed = self.state_elapsed()
        if elapsed > self.down_time_limit:
            self.logger.info(
                f"{self.get_state()} timeout "
                f"{elapsed} > {self.down_time_limit}"
            )
            self.set_state(STATE_CLOSED)
            return

        payload = self.get_payload()
        if payload == PAYLOAD_UP:
            self.set_state(STATE_OPENING)
        elif payload == PAYLOAD_STOP:
            self.set_state(STATE_PARTIAL)
        elif payload is not None:
            self.logger.info(f"discarding payload: {payload}")

    def state_opening(self):
        if self.upper_limit.is_pressed:
            self.set_state(STATE_OPEN)
            return

        self.down_motor.off()
        self.up_motor.on()

        elapsed = self.state_elapsed()
        if elapsed > self.up_time_limit:
            self.logger.info(
                f"{self.get_state()} timeout "
                f"{elapsed} > {self.up_time_limit}"
            )
            self.set_state(STATE_OPEN)
            return

        payload = self.get_payload()
        if payload == PAYLOAD_DOWN:
            self.set_state(STATE_CLOSING)
        elif payload == PAYLOAD_STOP:
            self.set_state(STATE_PARTIAL)
        elif payload is not None:
            self.logger.info(f"discarding payload: {payload}")

    def state_closed(self):
        self.motor_stop()
        if self._postion != 0.0:
            self._postion = 0.0
            self.publish_position()

        if self.upper_limit.is_pressed:
            self.set_state(STATE_ERROR)
            return

        payload = self.get_payload()
        if payload == PAYLOAD_UP:
            self.set_state(STATE_OPENING)
        elif payload is not None:
            self.logger.info(f"discarding payload: {payload}")

    def state_open(self):
        self.motor_stop()
        if self._postion != 100.0:
            self._postion = 100.0
            self.publish_position()

        if self.lower_limit.is_pressed:
            self.set_state(STATE_ERROR)
            return

        payload = self.get_payload()
        if payload == PAYLOAD_DOWN:
            self.set_state(STATE_CLOSING)
        elif payload is not None:
            self.logger.info(f"discarding payload: {payload}")

    def state_error(self):
        self.motor_stop()
        self.logger.critical("Entered error state, halting execution...")
        sys.exit(1)

    def state_initial(self):
        """Initial state of the cover."""
        self.logger.debug("determining position from initial state")
        self.motor_stop()

        if self.upper_limit.is_pressed and self.lower_limit.is_pressed:
            self.set_state(STATE_ERROR)
        elif self.upper_limit.is_pressed:
            self.set_state(STATE_OPEN)
        elif self.lower_limit.is_pressed:
            self.set_state(STATE_CLOSED)
        else:
            self.set_state(STATE_PARTIAL)

    def state_partial(self):
        self.motor_stop()

        if self.upper_limit.is_pressed and self.lower_limit.is_pressed:
            self.set_state(STATE_ERROR)
        elif self.upper_limit.is_pressed:
            self.set_state(STATE_OPEN)
        elif self.lower_limit.is_pressed:
            self.set_state(STATE_CLOSED)

        payload = self.get_payload()
        if payload == PAYLOAD_UP:
            self.set_state(STATE_OPENING)
        elif payload == PAYLOAD_DOWN:
            self.set_state(STATE_CLOSING)
        elif payload is not None:
            self.logger.info(f"discarding payload: {payload}")

    def handle(self):
        """Function to poll to handle events."""
        state = self.get_state()
        if state == STATE_INITIAL:
            self.state_initial()
        elif state == STATE_PARTIAL:
            self.state_partial()
        elif state == STATE_CLOSED:
            self.state_closed()
        elif state == STATE_OPEN:
            self.state_open()
        elif state == STATE_OPENING:
            self.state_opening()
        elif state == STATE_CLOSING:
            self.state_closing()
        elif state == STATE_ERROR:
            self.state_error()
        else:
            self.logger.error(f"Unknown state: {state}")
            self.set_state(STATE_ERROR)
            self.state_error()

    def motor_stop(self):
        self.up_motor.off()
        self.down_motor.off()


def on_message(client, userdata, msg, covers: List[Cover]):
    topic = msg.topic
    payload = msg.payload.decode("utf-8", errors="backslashreplace")
    logger.debug(f"new message on '{topic}' with payload '{payload}'")
    if payload in {PAYLOAD_UP, PAYLOAD_DOWN, PAYLOAD_STOP}:
        for cover in covers:
            if cover.set_topic == topic:
                cover.queue.put_nowait(payload)
                break
        else:
            logger.warning(f"unknown topic '{topic}' with payload '{payload}'")
    else:
        logger.warning(
            f"unknown message on '{topic}' with payload '{payload}'"
        )


def on_connect(client, userdata, flags, rc, covers: List[Cover]):
    logger.info(f"connected to MQTT server with code {rc}")

    for cover in covers:
        logger.info(f"subscribing to {cover.set_topic}")
        client.subscribe(cover.set_topic)


def start_daemon(hostname: str):
    """Starts the daemonic process."""
    handler = JournalHandler(SYSLOG_IDENTIFIER="cover")
    handler.setLevel(logging.DEBUG)
    formatter = logging.Formatter("[{name}] {message}", style="{")
    handler.setFormatter(formatter)

    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)
    root_logger.addHandler(handler)

    logger.debug("logging initialized")

    covers = []
    try:
        client = mqtt.Client(
            # TODO: add for version 2
            # callback_api_version=mqtt.CallbackAPIVersion.VERSION1
        )

        covers = [
            Cover(
                up_motor_pin=5,
                down_motor_pin=12,
                up_limit_pin=2,
                down_limit_pin=3,
                base_topic="/home/sunroom/right_window",
                up_time_limit=69.0,
                down_time_limit=70.0,
                client=client,
            ),
            Cover(
                up_motor_pin=6,
                down_motor_pin=13,
                up_limit_pin=4,
                down_limit_pin=17,
                base_topic="/home/sunroom/middle_window",
                up_time_limit=68.0,
                down_time_limit=70.0,
                client=client,
            ),
            Cover(
                up_motor_pin=19,
                down_motor_pin=16,
                up_limit_pin=27,
                down_limit_pin=22,
                base_topic="/home/sunroom/left_window",
                up_time_limit=78.0,
                down_time_limit=80.0,
                client=client,
            ),
        ]

        client.on_connect = functools.partial(on_connect, covers=covers)
        client.on_message = functools.partial(on_message, covers=covers)
        ssl_context = ssl.SSLContext()
        ssl_context.minimum_version = ssl.TLSVersion.TLSv1_3
        ssl_context.load_verify_locations("/etc/ssl/certs/ca-bundle.crt")
        client.tls_set_context(context=ssl_context)
        client.connect(hostname, 8883)
        client.loop_start()
    except Exception:
        logger.exception("failed to init")
        raise

    try:
        logger.info("Entering handler loop")
        while True:
            for cover in covers:
                cover.handle()
            time.sleep(0.02)
    except Exception:
        logger.exception("unhandled exception")
    finally:
        for cover in covers:
            try:
                cover.motor_stop()
            except BaseException:  # noqa: B036
                logger.exception(f"failed to stop motor for cover={cover}")


def main():
    parser = argparse.ArgumentParser(description="cover daemon")
    parser.add_argument(
        "hostname", type=str, help="MQTT server hostname or IPv4"
    )
    args = parser.parse_args()

    start_daemon(args.hostname)


if __name__ == "__main__":
    main()
