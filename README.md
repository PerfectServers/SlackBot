# Perfect Slack Bot

<p align="center">
    <a href="http://perfect.org/get-involved.html" target="_blank">
        <img src="http://perfect.org/assets/github/perfect_github_2_0_0.jpg" alt="Get Involed with Perfect!" width="854" />
    </a>
</p>

<p align="center">
    <a href="https://github.com/PerfectlySoft/Perfect" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_1_Star.jpg" alt="Star Perfect On Github" />
    </a>  
    <a href="http://stackoverflow.com/questions/tagged/perfect" target="_blank">
        <img src="http://www.perfect.org/github/perfect_gh_button_2_SO.jpg" alt="Stack Overflow" />
    </a>  
    <a href="https://twitter.com/perfectlysoft" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_3_twit.jpg" alt="Follow Perfect on Twitter" />
    </a>  
    <a href="http://perfect.ly" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_4_slack.jpg" alt="Join the Perfect Slack" />
    </a>
</p>

<p align="center">
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Swift-3.0-orange.svg?style=flat" alt="Swift 3.0">
    </a>
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Platforms-OS%20X%20%7C%20Linux%20-lightgray.svg?style=flat" alt="Platforms OS X | Linux">
    </a>
    <a href="http://perfect.org/licensing.html" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache-lightgrey.svg?style=flat" alt="License Apache">
    </a>
    <a href="http://twitter.com/PerfectlySoft" target="_blank">
        <img src="https://img.shields.io/badge/Twitter-@PerfectlySoft-blue.svg?style=flat" alt="PerfectlySoft Twitter">
    </a>
    <a href="http://perfect.ly" target="_blank">
        <img src="http://perfect.ly/badge.svg" alt="Slack Status">
    </a>
</p>

This is a starter template project for Slack Bot Servers.
In this template, a slack bot will join Slack channels, record all "cookies" sent by users, and reply user's query about cookies automatically.

## Prerequisites

Before building / testing or deploying your own Perfect Slack Bot into production, these steps *MUST* be well prepared:

- [Perfect Basics](http://www.perfect.org/docs/gettingStartedFromScratch.html)
- [Slack API Development](https://api.slack.com)
- An actual server with a FQDN (full qualified domain name) and an authorized certificate
- [Perfect Assistant](http://www.perfect.org/en/assistant/) will be used for building & deploying. It is optional, however, a Ubuntu 16.04 (virtual machine or docker image) with preinstalled Swift 3 would be required if not using Perfect Assistant.

## Quick Start

### Step 1. Clone This Project

Please clone this project by command:

```
$ git clone https://github.com/PerfectServers/SlackBot.git
```

There is a `config.json.sample` file in the project folder with content below. All blanks should be fulfilled before running.

``` json
{
  "token": "xoxb-YOURAPP-TOKENXXXXXXXXXXXXXXXXX",
  "bot" : "yourBotName",
  "bot_id": "YOUR_BOT_ID",
  "client_id": "XXXXXXXX.YYYYYYYYYY",
  "client_secret": "your-client-secret",
  "verify_token": "token-to-verify-by-your-app",
  "oauth_uri": "/v1/oauth",
  "message_uri": "/v1/message",
  "confirm_uri": "/v1/confirm",
  "serverName": "yourhost.yourcompany.domain",
  "cerPath": "/opt/certificates/yourcertificate.crt",
  "keyPath": "/opt/certificates/yourcertificate.key",
  "dbPath": "/var/opt/yoursqlite.db",
  "runAs": "yourUserName",
  "port": 443,
  "channels": {
    "channel1_id": "channel1_name",
    "channel2_id": "channel2_name"
  }
}
```

Details of this configuration json file will be discussed later in this article.

### Step 2. Register An Application for Your Slack Team

- On the [Slack API](https://api.slack.com), choose "Your Apps" to start a brand new app
- Bot Users: make a valid name for your bot user, and it will apply to the configuration
- Adding Permissions: in this example, permissions like "bot user", "channels:history", "channels.read" / "channels.write" and "chart:write:bot" for sending messages as bot are essentially required.
- Event Subscription: this demo requires at least four Slack events to subscribe: (1) `message.channels`; (2) `message.im`; (3) `reaction_added`; (4) `reaction_removed`.
- Enable Events by Setting Request URL. Given your server name is `myhost.com` and your configuration `message_uri` with `/v1/message`, then please input this requrest url with `https://myhost.com/v1/message_uri`. *NOTE* Slack will not identify protocols other than HTTPS and the port to server can only be 443.
- Install your app to your team.

If success, copy all essential configurations to your own `config.json` file, which `token` means the *`Bot User OAuth Access Token`*

### Step 3. Tricky Part: Get Your Bot's Slack ID

Slack Bot needs its id (not the display name) to work with, so it is a bit tricky to get such a name. Please read this section carefully to get the correct id:

- Open a web browser and navigate to [`users.list` Slack API page](https://api.slack.com/methods/users.list/test)
- Choose the right team token of your app and click `Test Method`
- If success, click the link `(open raw response)` and a raw but pretty JSON text shall present.
- Search the bot's display name from the JSON text.
- Copy the bot's Slack ID to your configuration file.

### Step 4. Tricky Part II: Choose The Channels to Spy (Optional but Should Check for Avoiding Spam)

Although many bot distributors are happy to allow their bots to join as many channels or groups as possible, you may want to restrict the bot behaviour in a few specific channels.

To archive this objective, follow the instructions below:

- Open a web browser and navigate to [`channels.list` Slack API page](https://api.slack.com/methods/channels.list/test)
- Choose the right team token of your app and click `Test Method`
- If success, click the link `(open raw response)` and a raw but pretty JSON text shall present.
- Choose the channels for spying, and copy each `id` and `name` pair into your `config.json` file.

*NOTE* If you prefer to allow the bot app accessing all channels, please add a snippet below after the configuration loading code:

``` swift
Curl("https://slack.com/api/channels.list?token=\(token)") { ret in
  do {
    guard let b = ret,
      let info = try b.jsonDecode() as? [String:Any],
      let ok = info["ok"] as? Bool,
      let channels = info["channels"] as? [Any] else {
        Print("channel parse::ok(fault)")
        return nil
    }//end guard
    guard ok, channels.count > 0 else {
      Print("channel parse::ok(\(ok))")
      return nil
    }//end
    channels.forEach { channel in
      let ch = channel as? [String: Any] ?? [:]
      guard let id = ch["id"] as? String,
      let name = ch["name"] as? String else {
        return
      }//end guard

      // CAUTION: Append all channels into the cache
      global.channels[id] = name
    }//next
  }catch(let err) {
    Print("parseChannels::\(err)")
    return nil
  }// end do  
}//end curl
```

### Step 5. Build & Deploy The Bot Server

It is strongly recommended to use [Perfect Assistant](http://www.perfect.org/en/assistant/) to automate all building / deployment jobs as required essentially for such a Slack Bot Server.

However, if other cloud services than AWS / Google Cloud were considered, a install script `install.sh.sample` listed the project folder might be helpful at this point as steps below:

- (1) Build on you local Ubuntu 16.04, i.e., VM or Docker. Run `$ swift build -c release` to create a release
- (2) Shipped the binaries to your production server (might company with Swift runtime library if need)
- (3) Copy the `config.service` and `config.json` to the server. Sample of `config.service` can be found in the same project folder.
- (4) Place all your certificates file in proper folder on server with sufficient but secured permissions.
- (5) Modify the `config.json` on your server to match all variables required, especially the certificates path, the database path.
- (6) Modify the `config.service` on your server to match all paths required.
- (7) Using `$ sudo systemctl enable config.service` to register your server app into services, then it can start up automatically by system account.
- (8) Start the server. You can reset the server or run `$ sudo systemctl restart slackbot` if the service name is `slackbot`.

Without Perfect Assistant, the all above steps will be also very tricky. So read check out the files content below before the building & deployment:

#### Config.service Example

```
[Unit]
Description=Your Slack Bot Server

[Service]
Type=simple
WorkingDirectory=/var/opt
ExecStart=/path/to/yourApp/PerfectTemplate
Restart=always
PIDFile=/var/run/yourSlackBotApp.pid

[Install]
WantedBy=multi-user.target
```

#### Installation Script Example

```
# Installation Script Example
# Suppose your server app is named as `slackbot`
# Please make sure your server installed Swift runtime binaries,
# i.e., LD_LIBRARY_PATH="/usr/lib/yourSwiftInstalationPath"
# define the variables
RPO=slackbot
TGZ=/tmp/$RPO.tgz
SVC=$RPO.service
CFG=$RPO.json
APP=/tmp/app.tgz
SERVER=yoursshLoginUserName@yourhost.yourdomain
LOCALVM=your.local.ubuntu.virtual.machine

# pack source code to local vm
tar czvf $TGZ Package.swift Sources
scp $TGZ $LOCALVM:/tmp

# build the binary on local VM
ssh $LOCALVM "cd /tmp;rm -rf $RPO;mkdir $RPO; cd $RPO; tar xzvf $TGZ;swift build -c release;cd .build/release;tar czvf $APP PerfectTemplate *.so"

# ship the binaries back to your production server
scp $LOCALVM:$APP $APP
scp $APP $SERVER:$APP
scp $SVC $SERVER:/tmp/$SVC
scp $CFG $SERVER:/tmp/$CFG

# perform installation & register your new app as a service .
ssh $SERVER "cd /opt;sudo -S rm -rf $RPO;sudo -S mkdir $RPO;cd $RPO;sudo -S tar xzvf $APP;sudo -S cp /tmp/$SVC .;sudo -S cp /tmp/$CFG .;sudo -S systemctl disable $RPO;sudo -S systemctl enable /opt/$RPO/$SVC;sudo -S systemctl start $RPO;sudo -S systemctl status $RPO"
```

### Step 6. Back To Slack API App Settings

Once booting your server, then please go back to your slack api page to confirm all the settings, especially the oauth authentication page:

- Verify the Event Subscription `Request URL`
- Goto your slack channel, invite the bot. *NOTE* add a testing channel for testing may be helpful
- Test the bot by sending it cookies and directly message it.

## Issues

We are transitioning to using JIRA for all bugs and support related issues, therefore the GitHub issues has been disabled.

If you find a mistake, bug, or any other helpful suggestion you'd like to make on the docs please head over to [http://jira.perfect.org:8080/servicedesk/customer/portal/1](http://jira.perfect.org:8080/servicedesk/customer/portal/1) and raise it.

A comprehensive list of open issues can be found at [http://jira.perfect.org:8080/projects/ISS/issues](http://jira.perfect.org:8080/projects/ISS/issues)

## Further Information
For more information on the Perfect project, please visit [perfect.org](http://perfect.org).
