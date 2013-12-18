# Inject-o-bot Documentation
This developer-friendly IRC bot provides an API to inject code as plugins so that teams of developers can add their own functionality. Each plugin runs as an unprivileged user in its own `chroot` sandbox and communicates via sockets with a master process that allows it to interact with the IRC server, channels and users. The plugins themselves are run in a context which provides some commonly used modules and a nice API to interact with the master process. This means you can:

* Generate messages for users and channels
* Call out to web APIs via `request`
* Access the chrooted filesystem with `fs`
* Access built-in modules like `crypto`, `fs`, `http`, `net`, `path`
* Access common modules like `_`, `async`, `cheerio`, `coffee`, `glob`, `marked`, `moment`, `npm`, `q`

Because of the chroot, you _cannot_ call shell scripts or any typical system-installed libraries or commands, nor can you modify other scripts or modules.

## Installation & Usage
The bot can be installed via npm (may require `sudo`):

```bash
npm install -g injectobot
```

Once installed, it can be run via the `injectobot` command, which requires `sudo` in order to create the plugin chroot jails. Unless a `--host` is passed, it will not connect to an IRC channel and instead will dump all messages to the terminal, which is useful for testing plugins locally.

```bash
# Run the bot, connecting to IRC
sudo injectobot --host chat.freenode.org --name 'mybot'

# Start the bot for testing locally (no IRC)
sudo injectobot --name 'mybot' --listen 8000

# Simulate an incoming IRC message
http localhost:8000/test message=='mybot: help'
```

## Basic Plugin Example
A very basic plugin which listens to a command `echo` and replies back to the sender or room any text that follows the command would look like this (both CoffeeScript and Javascript are supported):

```coffeescript
bot.command 'echo', (from, to, args) ->
    bot.reply from, to, args
```

## Displaying Help
You can listen to the `help` command to display information about your plugin. For example:

```coffeescript
bot.command 'help', (from, to, args) ->
    switch args
        when ''
            bot.reply from, to, 'echo [message]: say a message back to you'
        when 'echo'
            bot.reply from, to, 'Echo a message back to the sender or channel'

```

## Bot Plugin API
The bot's plugin API provides a layer above the interprocess communication mechanism to make interacting with the master process more like typical programming. The API is accessed via the `bot` variable.

### Attributes

| Attribute | Description            |
| --------- | ---------------------- |
| name      | The bot's IRC nickname |

### Methods

#### bot.use (handler)
Register a handler `(from, to, message)` that gets invoked each time a message is received, including any message sent to any channel that the bot is in. It is up to you to filter out the messages you care about.

```coffeescript
bot.use (from, to, message) ->
    # Do stuff here!
```

#### bot.command (cmd, handler)
Register a handler `(from, to, args)` that gets invoked each time a command is sent to the bot, either via a private message or via the bot's name in a channel (e.g. `botname command ...`). `args` will contain all text after the command as a single string.

```coffeescript
bot.command 'help', (from, to, args) ->
    # Do stuff here!
```

#### bot.interval (milliseconds, handler)
Run a function at an interval in milliseconds. This is a shortcut for `setInterval` that flips the parameter order to make it easier to use with CoffeeScript.

```coffeescript
bot.interval 5000, ->
    # Do stuff here every five seconds!
```

#### bot.say (to, message)
Say a message to a user or channel. Channels must include the `#` character.

```coffeescript
bot.say '#mychannel', 'Hello, world!'
```

#### bot.reply (from, to, message)
Reply to a message. This is like `say`, except contains logic to either reply to a private message or reply into the channel, which is why you need to pass both `from` and `to` into it.

```coffeescript
bot.reply from, to, 'Hello, world!'
```

## Uploading a Plugin
You can upload a plugin by doing an `HTTP PUT` to this server. __Warning__: there are currently zero access controls. It may be a good idea to prefix your plugins with a unique name to prevent clashes with other team members.

If a plugin requires a secret such as an API token then it should be set in a variable that ends in `TOKEN` or `SECRET`, for example `MY_TOKEN = 'some-secret-string'`. When reading plugins this string will be replaced to prevent leaking of secrets.

```http
PUT http://localhost:3000/plugins/:name HTTP/1.1
Content-Type: application/json

{
    "type": "coffee",
    "script": "bot.command 'echo', ..."
}
```

### Parameters
| Name     | Description                              | Default |
| -------- | ---------------------------------------- | ------- |
| `name`   | The plugin name (in the URL)             | -       |
| `type`   | The script type, either `js` or `coffee` | `js`    |
| `script` | The script text                          | -       |

#### HTTPie Example
Get [HTTPie](https://github.com/jkbr/httpie) via `pip install --upgrade https://github.com/jkbr/httpie/tarball/master`. You need at least version `0.8` to support the `=@` syntax below.

```bash
http put localhost:3000/plugins/test type=js script=@myscript.js
```

## Listing All Plugins
You can list all installed plugin names (including extension type) with an `HTTP GET` call to the server. A list of strings is returned.

```http
GET http://localhost:3000/plugins HTTP/1.1
```

#### HTTPie Example
```bash
http localhost:3000/plugins
```

## Reading a Plugin
You can read a plugin's source code, minus any secrets, with an `HTTP GET` call to the server.

```http
GET http://localhost:3000/plugins/:name?type=:type HTTP/1.1
```

### Parameters
| Name     | Description                              | Default |
| -------- | ---------------------------------------- | ------- |
| `name`   | The plugin name (in the URL)             | -       |
| `type`   | The script type, either `js` or `coffee` | `js`    |

#### HTTPie Example
```bash
http localhost:3000/plugins/test type==js
```

## Deleting a Plugin
You can delete a plugin by doing an `HTTP DELETE` to this server. __Warning__: there are currently zero access controls, so please be responsible.

```http
DELETE http://localhost:3000/plugins/:name HTTP/1.1
```

#### HTTPie Example
```bash
http delete localhost:3000/plugins/test type==coffee
```

## Advanced Usage
The following sections describe advanced behavior.

### Basic Security
This bot has very little security built-in, and is intended for small teams of developers who want to allow members to quickly write fun little plugins for the team. Some ideas for locking it down:

* Limit who can PUT/DELETE via `iptables` whitelists
* Require a password as an argument to plugin commands

### Custom Dependencies
Built-in modules are described at the top of this document, but sometimes there may be a module you wish to use that isn't included. You can install custom dependencies for your script programmatically via the `npm` module. __Note__: only pure javascript modules are supported. C/C++ extensions are prohibited because they could contain inline assembly and potentially wreak havoc. Here is an example:

```coffeescript
npm.load {}, (err) ->
    if err then # ...

    npm.commands.install ['module1', 'module2'], (err) ->
        if err then # ...

        # Now you can load your modules!
        module1 = require 'module1'
        module2 = reuqire 'module2'
```

## License
Copyright &copy; 2013 Daniel G. Taylor

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
