use std::{
    sync::mpsc::Receiver,
    time::{Duration, Instant},
};

use anyhow::Context;
use rppal::gpio::{self, Gpio, InputPin, OutputPin};
use rumqttc::{QoS, SubscribeFilter};
use tokio::{sync::mpsc::Sender, time::sleep};

pub enum Payload {
    Up,
    Down,
    Stop,
}

#[derive(Debug)]
pub enum State {
    Closed,
    Closing,
    Open,
    Opening,
    Partial,
    Initial,
    Error,
}

impl Default for State {
    fn default() -> Self {
        State::Initial
    }
}

pub struct Cover {
    up_motor: OutputPin,
    down_motor: OutputPin,
    up_limit: InputPin,
    down_limit: InputPin,
    up_time_limit: Duration,
    down_time_limit: Duration,
    base_topic: &'static str,
    state: State,
    state_start: Instant,
    position: Option<f32>,
    // payloads: Receiver<Payload>,
}

fn pin_n(gpio: &Gpio, n: u8) -> anyhow::Result<gpio::Pin> {
    gpio.get(n)
        .with_context(|| format!("Failed to get pin {n}"))
}

impl Cover {
    pub fn new(
        gpio: &Gpio,
        up_motor_pin: u8,
        down_motor_pin: u8,
        up_limit_pin: u8,
        down_limit_pin: u8,
        up_time_limit: Duration,
        down_time_limit: Duration,
        base_topic: &'static str,
    ) -> anyhow::Result<Self> {
        // let (payloads_sender, payloads_receiver): (Sender<Payload>, Receiver<Payload>) =
        //     tokio::sync::mpsc::channel(24);
        Ok(Self {
            up_motor: pin_n(gpio, up_motor_pin)?.into_output(),
            down_motor: pin_n(gpio, down_motor_pin)?.into_output(),
            up_limit: pin_n(gpio, up_limit_pin)?.into_input(),
            down_limit: pin_n(gpio, down_limit_pin)?.into_input(),
            up_time_limit,
            down_time_limit,
            base_topic,
            state: Default::default(),
            state_start: Instant::now(),
            position: None,
        })
    }

    pub fn topic(&self) -> &'static str {
        self.base_topic
    }

    pub fn subscribe_filter(&self) -> SubscribeFilter {
        SubscribeFilter::new(self.base_topic.to_string(), QoS::AtMostOnce)
    }

    /// Get the duration in seconds of the current state.
    fn state_elapsed(&self) -> Duration {
        Instant::now().duration_since(self.state_start)
    }

    /// Set the current cover state.
    async fn set_state(&mut self, state: State) {
        let elapsed: Duration = self.state_elapsed();
        log::debug!(
            "Changing state from {:?} to {:?} after {:?}",
            self.state,
            state,
            elapsed
        );

        match self.state {
            State::Opening => {
                self.up_motor.set_low();
                self.down_motor.set_high();
                sleep(Duration::from_millis(120)).await;
                self.down_motor.set_low();
            }
            State::Closing => {
                self.down_motor.set_low();
                self.up_motor.set_high();
                sleep(Duration::from_millis(120)).await;
                self.down_motor.set_low();
            }
            _ => (),
        }

        if !matches!(state, State::Open | State::Closed) {
            match self.state {
                State::Opening => {
                    if let Some(position) = self.position.as_mut() {
                        *position +=
                            elapsed.as_secs_f32() * (100.0 / self.up_time_limit.as_secs_f32());
                        *position = position.clamp(0.0, 99.0);
                    }
                }
                State::Closing => {
                    if let Some(position) = self.position.as_mut() {
                        *position -=
                            elapsed.as_secs_f32() * (100.0 / self.down_time_limit.as_secs_f32());
                        *position = position.clamp(1.0, 100.0);
                    }
                }
                _ => (),
            }
        }

        self.state = state;
        self.state_start = Instant::now();
    }

    fn publish_position(&self) {
        if let Some(position) = self.position {
            let p: String = format!("{position:.0}");
            log::debug!("publishing {p}");
            todo!("self.client.publish(self.position_topic, p)");
        }
    }

    // /// Gets a payload from the queue if avaliable.
    // fn get_payload(self) -> Optional[str] {
    //     try:
    //         payload = self.queue.get_nowait()
    //     except queue.Empty:
    //         return None
    //     else:
    //         self.logger.debug(f"new payload: {payload}")
    //         return payload

    // fn state_closing(self) {
    //     if self.lower_limit.is_pressed:
    //         self.set_state(STATE_CLOSED)
    //         return

    //     self.up_motor.value = 0
    //     self.down_motor.value = 1

    //     elapsed = self.state_elapsed()
    //     if elapsed > self.down_time_limit:
    //         self.logger.info(
    //             f"{self.get_state()} timeout "
    //             f"{elapsed} > {self.down_time_limit}"
    //         )
    //         self.set_state(STATE_CLOSED)
    //         return

    //     payload = self.get_payload()
    //     if payload == PAYLOAD_UP:
    //         self.set_state(STATE_OPENING)
    //     elif payload == PAYLOAD_STOP:
    //         self.set_state(STATE_PARTIAL)
    //     elif payload is not None:
    //         self.logger.info(f"discarding payload: {payload}")

    // fn state_opening(self) {
    //     if self.upper_limit.is_pressed:
    //         self.set_state(STATE_OPEN)
    //         return

    //     self.down_motor.value = 0
    //     self.up_motor.value = 1

    //     elapsed = self.state_elapsed()
    //     if elapsed > self.up_time_limit:
    //         self.logger.info(
    //             f"{self.get_state()} timeout "
    //             f"{elapsed} > {self.up_time_limit}"
    //         )
    //         self.set_state(STATE_OPEN)
    //         return

    //     payload = self.get_payload()
    //     if payload == PAYLOAD_DOWN:
    //         self.set_state(STATE_CLOSING)
    //     elif payload == PAYLOAD_STOP:
    //         self.set_state(STATE_PARTIAL)
    //     elif payload is not None:
    //         self.logger.info(f"discarding payload: {payload}")

    // fn state_closed(self) {
    //     self.motor_stop()
    //     if self._postion != 0.0:
    //         self._postion = 0.0
    //         self.publish_position()

    //     if self.upper_limit.is_pressed:
    //         self.set_state(STATE_ERROR)
    //         return

    //     payload = self.get_payload()
    //     if payload == PAYLOAD_UP:
    //         self.set_state(STATE_OPENING)
    //     elif payload is not None:
    //         self.logger.info(f"discarding payload: {payload}")

    // fn state_open(self) {
    //     self.motor_stop()
    //     if self._postion != 100.0:
    //         self._postion = 100.0
    //         self.publish_position()

    //     if self.lower_limit.is_pressed:
    //         self.set_state(STATE_ERROR)
    //         return

    //     payload = self.get_payload()
    //     if payload == PAYLOAD_DOWN:
    //         self.set_state(STATE_CLOSING)
    //     elif payload is not None:
    //         self.logger.info(f"discarding payload: {payload}")

    // fn state_error(self) {
    //     self.motor_stop()
    //     self.logger.critical("Entered error state, halting execution...")
    //     sys.exit(1)

    // /// Initial state of the cover.
    // fn state_initial(self) {
    //     self.logger.debug("determining position from initial state")
    //     self.motor_stop()

    //     if self.upper_limit.is_pressed and self.lower_limit.is_pressed:
    //         self.set_state(STATE_ERROR)
    //     elif self.upper_limit.is_pressed:
    //         self.set_state(STATE_OPEN)
    //     elif self.lower_limit.is_pressed:
    //         self.set_state(STATE_CLOSED)
    //     else:
    //         self.set_state(STATE_PARTIAL)

    // async fn state_partial(&mut self) {
    //     self.motor_stop();

    //     match (self.up_limit.is_high(), self.down_limit.is_high()) {
    //         (true, true) => self.set_state(State::Error).await,
    //         (true, false) => self.set_state(State::Open).await,
    //         (false, true) => self.set_state(State::Closed).await,
    //         _ => (),
    //     };

    //     todo!("Get payload")

    //     // payload = self.get_payload()
    //     // if payload == PAYLOAD_UP:
    //     //     self.set_state(STATE_OPENING)
    //     // elif payload == PAYLOAD_DOWN:
    //     //     self.set_state(STATE_CLOSING)
    //     // elif payload is not None:
    //     //     self.logger.info(f"discarding payload: {payload}")
    // }

    async fn payload_up(&mut self) {}

    pub async fn payload(&mut self, payload: Payload) {
        match payload {
            Payload::Up => self.payload_up().await,
            Payload::Down => self.payload_down().await,
            Payload::Stop => self.payload_stop().await,
        }
    }

    // pub async fn handle(&mut self) {
    //     match self.state {
    //         State::Closed => todo!(),
    //         State::Closing => todo!(),
    //         State::Open => todo!(),
    //         State::Opening => todo!(),
    //         State::Partial => todo!(),
    //         State::Initial => self.state_partial().await,
    //         State::Error => todo!(),
    //     }
    // }

    pub fn motor_stop(&mut self) {
        self.up_motor.set_low();
        self.down_motor.set_low();
    }
}
