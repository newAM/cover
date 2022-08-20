mod cover;

use std::time::Duration;

use anyhow::Context;
use cover::Cover;
use rppal::gpio::Gpio;
use rumqttc::Packet;
use tokio::sync::mpsc::{Receiver, Sender};

// #[derive(Debug)]
// pub enum Window {
//     Right,
//     Middle,
//     Left,
// }

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    ctrlc::set_handler(|| std::process::exit(0)).context("Failed to set SIGINT handler")?;
    systemd_journal_logger::init().context("Failed to initialize logging")?;

    let gpio: Gpio = Gpio::new().context("Failed to create a GPIO")?;

    let covers = [
        Cover::new(
            &gpio,
            5,
            12,
            2,
            3,
            Duration::from_secs(67),
            Duration::from_secs(70),
            "/home/sunroom/right_window",
        )?,
        Cover::new(
            &gpio,
            6,
            13,
            4,
            17,
            Duration::from_secs(67),
            Duration::from_secs(70),
            "/home/sunroom/middle_window",
        )?,
        Cover::new(
            &gpio,
            19,
            16,
            27,
            22,
            Duration::from_secs(78),
            Duration::from_secs(80),
            "/home/sunroom/left_window",
        )?,
    ];

    let (position_secondary, position_main): (Sender<u8>, Receiver<u8>) =
        tokio::sync::mpsc::channel(24);

    let mqtt_options: rumqttc::MqttOptions = rumqttc::MqttOptions::new("cover", "10.0.0.4", 1883);
    let (mut mqtt_client, mut eventloop) = rumqttc::AsyncClient::new(mqtt_options, 24);

    mqtt_client
        .subscribe_many(covers.iter().map(|c| c.subscribe_filter()))
        .await
        .context("Failed to susbscribe to topics")?;

    match eventloop.poll().await {
        Ok(rumqttc::Event::Incoming(Packet::Publish(publish))) => {
            if let Some(c) = covers.iter().find(|c| c.topic() == publish.topic) {
                todo!("")
                // c.publish
            } else {
                log::error!("Unknown topic: {}", publish.topic);
            }
        }
        Ok(rumqttc::Event::Incoming(i)) => log::warn!("Unhandled incoming packet: {i:?}"),
        Ok(rumqttc::Event::Outgoing(o)) => log::debug!("Outgoing: {o:?}"),
        Err(e) => log::error!("{e:?}"),
    }

    Ok(())
}
