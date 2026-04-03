/// This module provides the logic for sending mail using a [`Mailer`](/gcourier/gcourier/types.html#Mailer).
/// As of writing, the library implements only one `Mailer`, which is `SmtpMailer`.
import gcourier/message.{type Message}
import gcourier/mug/mug
import gleam/bit_array
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

type Mailer {
  SmtpMailer(
    host: String,
    port: Int,
    username: String,
    password: String,
    auth: Bool,
  )
}

pub type Error {
  FailedToConnect(mug.Error)
  FailedToReceive(mug.Error)
  InvalidUtf8Response(BitArray)
  FailedToSend(mug.Error)
  FailedToUpgrade(mug.Error)
}

pub fn send(
  host: String,
  port: Int,
  auth: Option(#(String, String)),
  message: Message,
) {
  let mailer = case auth {
    Some(#(username, password)) ->
      SmtpMailer(host:, port:, username:, password:, auth: True)
    None -> SmtpMailer(host:, port:, username: "", password: "", auth: False)
  }

  send_smtp(mailer, message)
}

fn send_smtp(mailer: Mailer, msg: Message) {
  use socket <- result.try(
    connect_smtp(SmtpMailer(
      host: mailer.host,
      port: mailer.port,
      username: mailer.username,
      password: mailer.password,
      auth: mailer.auth,
    )),
  )

  let from_cmd = "MAIL FROM:<" <> mailer.username <> ">"
  use _ <- result.try(socket_send_checked(socket, from_cmd))
  use _ <- result.try(socket_receive(socket))

  let rcpt =
    list.map(msg.to, fn(r) {
      let to_cmd = "RCPT TO:<" <> r <> ">"
      use _ <- result.try(socket_send_checked(socket, to_cmd))
      socket_receive(socket)
    })
    |> result.all()
  use _ <- result.try(rcpt)

  use _ <- result.try(socket_send_checked(socket, "DATA"))
  use _ <- result.try(socket_receive(socket))

  use _ <- result.try(socket_send_checked(socket, message.render(msg)))
  use _ <- result.try(socket_receive(socket))

  use _ <- result.try(socket_send_checked(socket, "QUIT"))
  use _ <- result.try(socket_receive(socket))
  Ok(Nil)
}

fn socket_send_checked(socket: mug.Socket, value: String) -> Result(Nil, Error) {
  socket_send(socket, value)
}

fn socket_send(socket: mug.Socket, value: String) -> Result(Nil, Error) {
  mug.send(socket, <<{ value <> "\r\n" }:utf8>>)
  |> result.map_error(FailedToSend)
}

fn socket_receive(socket: mug.Socket) -> Result(String, Error) {
  use packet <- result.try(
    mug.receive(socket, 5000) |> result.map_error(FailedToReceive),
  )
  bit_array.to_string(packet)
  |> result.replace_error(InvalidUtf8Response(packet))
}

fn connect_smtp(mailer: Mailer) -> Result(mug.Socket, Error) {
  use socket <- result.try(
    mug.new(mailer.host, mailer.port)
    |> mug.timeout(milliseconds: 500)
    |> mug.connect()
    |> result.map_error(FailedToConnect),
  )

  use resp <- result.try(socket_receive(socket))

  let ehlo = case string.contains(resp, "ESMTP") {
    True -> socket_send(socket, "EHLO " <> mailer.host)
    False -> socket_send(socket, "HELO " <> mailer.host)
  }
  use _ <- result.try(ehlo)

  use helo_resp <- result.try(socket_receive(socket))

  let ehlo = case string.contains(helo_resp, "STARTTLS") {
    False -> #(helo_resp, socket) |> Ok
    True -> {
      use _ <- result.try(socket_send_checked(socket, "STARTTLS"))
      use _ <- result.try(
        mug.receive(socket, 5000) |> result.map_error(FailedToReceive),
      )

      use socket <- result.try(
        mug.upgrade(socket, mug.DangerouslyDisableVerification, 10_000)
        |> result.map_error(FailedToUpgrade),
      )
      use _ <- result.try(socket_send_checked(socket, "EHLO " <> mailer.host))
      use resp <- result.try(socket_receive(socket))
      #(resp, socket) |> Ok
    }
  }
  use #(helo_resp, socket) <- result.try(ehlo)

  use _ <- result.try(case mailer.auth {
    False -> Ok(Nil)
    True -> auth_user(socket, mailer, helo_resp)
  })

  socket
  |> Ok
}

fn auth_user(
  socket: mug.Socket,
  mailer: Mailer,
  helo_resp: String,
) -> Result(Nil, Error) {
  case string.contains(helo_resp, "AUTH") {
    False -> {
      io.println_error(
        "SMTP server does not support authentication. Proceeding as unauthenticated user.",
      )
      |> Ok
    }
    True -> {
      use _ <- result.try(socket_send_checked(socket, "AUTH LOGIN"))
      use _ <- result.try(socket_receive(socket))
      // todo: check resp
      use _ <- result.try(socket_send_checked(
        socket,
        mailer.username
          |> bit_array.from_string()
          |> bit_array.base64_encode(True),
      ))

      use _ <- result.try(socket_receive(socket))
      use _ <- result.try(socket_send_checked(
        socket,
        mailer.password
          |> bit_array.from_string()
          |> bit_array.base64_encode(True),
      ))
      use _ <- result.try(socket_receive(socket))
      Ok(Nil)
    }
  }
}
