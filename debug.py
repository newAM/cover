from gpiozero import Button
import time

while True:
    for pin in [2, 3, 4, 17, 22, 27]:
        button = Button(pin)
        print(f"{pin}={button.is_pressed}")
    time.sleep(1)
