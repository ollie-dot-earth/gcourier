import gcourier
import simplifile

// Note: gleam/erlang removed get_line in v1.0.0
import gleam/option.{None, Some}
import gleam/string

pub fn main() {
  let sender_email = input("Enter sender's gmail address: ")
  let sender_password = input("Enter sender's gmail password: ")
  let recipient_email = input("Enter recipient's email: ")
  let subject = input("Subject: ")
  let body = input("Body: ")
  let attach = input("Attach file? (y/N)")

  let msg =
    gcourier.new_message(gcourier.Sender(sender_email, None))
    |> gcourier.add_recipient(gcourier.To(recipient_email))
    |> gcourier.set_subject(subject)
    |> gcourier.set_content(gcourier.Text(body))

  let msg = case attach {
    "y" -> {
      let assert Ok(content) = simplifile.read_bits("./README.md")

      msg |> gcourier.add_attachment(content, "README.md", "text/markdown")
    }

    _ -> msg
  }

  gcourier.send(
    "smtp.gmail.com",
    587,
    Some(#(sender_email, sender_password)),
    msg,
  )
}

// External function to get user input (replacement for removed erlang.get_line)
@external(erlang, "io", "get_line")
fn get_line(prompt: String) -> String

fn input(prompt: String) -> String {
  let input = get_line(prompt)
  string.trim_end(input)
}
