_ = require 'lodash'
async = require 'async'
cheerio = require 'cheerio'
chroot = require 'chroot'
coffee = require 'coffee-script'
crypto = require 'crypto'
dns = require 'dns'
fs = require 'fs'
glob = require 'glob'
marked = require 'marked'
moment = require 'moment'
npm = require 'npm'
q = require 'q'
request = require 'request'

name = process.argv[3]

# Load the script
script = fs.readFileSync "#{__dirname}/plugins/#{name}", 'utf-8'

# Setup a basic API
bot =
    name: process.argv[2]
    nameRe: new RegExp("^#{process.argv[2]}:?")
    handlers: []

    # Register a handler for all messages
    use: (handler) ->
        bot.handlers.push [null, handler]

    # Register a handler for a command
    command: (command, handler) ->
        bot.handlers.push [new RegExp("^.*?#{command}\\s*(.*)"), handler]

    # Run a function at an interval
    interval: (milliseconds, handler) ->
        setInterval handler, milliseconds

    # Say a message to a user or channel
    say: (to, message) ->
        process.send { action: 'say', to, message }

    # Send a reply, either in a private message if the original message
    # was private, otherwise into a channel
    reply: (from, to, message) ->
        if to is bot.name then to = from
        bot.say to, message

# Handle messages from the master process
process.on 'message', (data) ->
    switch data.action
        when 'message'
            for [re, handler] in bot.handlers
                if re is null
                    handler(data.from, data.to, data.message)
                else if data.to is bot.name or bot.nameRe.exec data.message
                    match = re.exec data.message
                    if match
                        handler data.from, data.to, match[1]

# Report failures back to the master process
process.on 'uncaughtException', (err) ->
    process.send action: 'error', name: name, stack: err.stack
    process.exit()

# DNS lookup hack for chroot, see https://github.com/joyent/node/issues/3399
dns.lookup = (domain, family, callback) ->
    dns.resolve4 domain, callback or family

# Drop privs and force a filesystem jail
chroot "#{__dirname}/jails/#{name}", process.argv[4]

# Run the plugin! We use eval rather than vm.runInThisContext
# to provide access to the current locals without sandboxing
# the script.
if /\.coffee$/.exec name
    script = coffee.compile script, bare: true

eval script
