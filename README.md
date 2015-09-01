Mailtool
========

This is a mail tool, which brings together nodemailer for sending and
browserbox for recieving mails and you can store configurations for
both in a common configfile.  Passwords are stored in external files, 
which are referenced in config.

Configuration
-------------

Configuration brings together configuration of [NodeMailer](https://github.com/andris9/Nodemailer)
(in *transport* section) and [browserbox](https://github.com/whiteout-io/browserbox) 
(in *mailbox* section).

Example:

Default configuration resides in `~/.mailtool/config.cson`.  Paths to passwords are relative to 
config file.

```
Private:
	mailbox:
		type: 'imap'
		host: 'some.cool.host'
		port: 993
		secure: true
		auth:
			user: 'donald'
			pass: "passwords/Private-mailbox-auth"

Business:
	transport:
		host: 'smtp.entenhausen.com'
		port: 465
		auth:
			user: 'phantomas'
			pass: "passwords/Business-transport-auth"
		secure: true
		rejectUnauthorized: false

	mailbox:
		type: 'imap'
		host: 'imap.entenhausen.com'
		port: 993
		secure: true
		auth:
			user: 'phantomas'
			pass: "passwords/Business-mailbox-auth"

	dailyReport:
		from: "Phantomas <phantomas@entenhausen.com>"
		subject: "Daily Report"
		to: "news@entenhausen.com"

	default:
		from: "Phantomas <phantomas@entenhausen.com>"

		signature: """
			Phantomas
			World Saviour

			Entenhausen
		"""
```
