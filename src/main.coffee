#!/usr/bin/env coffee

child_process = require 'child_process'
express = require 'express'
fs = require 'fs'
hljs = require 'highlight.js'
irc = require 'irc'
marked = require 'marked'
os = require 'os'

options = require('optimist')
    .usage('Usage: $0 [options]')
    .options('n', alias: 'name', default: 'electricsheep')
    .options('h', alias: 'host')
    .options('p', alias: 'port', default: 6697)
    .options('s', alias: 'secure', default: true)
    .options('c', alias: 'channels', default: '#bot-test')
    .options('u', alias: 'user', default: 'nobody')
    .options('l', alias: 'listen', default: 3000)
    .argv

USERNAME = options.name
HELP = new RegExp "\\s*#{USERNAME}:?\\s+help$"

plugins = {}

# Handle an IPC message from a child process
handlePluginMessage = (data) ->
    switch data.action
        when 'error'
            console.log "#{data.name} crashed!"
            console.log data.stack
            # Unload the plugin
            delete plugins[data.name]
        when 'say'
            client.say data.to, data.message

# Load a plugin, start the child process, etc
loadPlugin = (name) ->
    console.log "Loading plugin #{name}"
    child = child_process.fork "#{__dirname}/runner.coffee", [USERNAME, name, options.user]
    child.on 'message', handlePluginMessage
    child.on 'error', ->
        console.log "#{name} plugin error!"
    child.on 'exit', ->
        console.log "#{name} plugin exited!"
    plugins[name] = child

# Got an IRC message, now send it along to plugins
handleIrcMessage = (from, to, message) ->
    if (to is USERNAME and message is 'help') or HELP.exec message
        target = if to is USERNAME then from else to
        client.say target, "Documentation: http://#{os.hostname()}:#{options.listen}/\nCommands:\n"
    
    for name, plugin of plugins
        plugin.send { action: 'message', from, to, message }

# IRC client setup
if options.host
    console.log "Connecting to #{options.host}:#{options.port} as #{USERNAME}"
    client = new irc.Client options.host, USERNAME,
        port: options.port
        secure: options.secure
        selfSigned: true
        certExpired: true
        userName: USERNAME
        realName: USERNAME
        channels: options.channels.split(',')

    client.addListener 'message', handleIrcMessage

    client.addListener 'error', (message) ->
        console.error message
else
    # Mock the client for testing
    client =
        say: (to, msg) ->
            console.log "@#{to}: #{msg}"

# Load all plugins
for name in fs.readdirSync("#{__dirname}/plugins")
    loadPlugin name

# Setup marked with code highlighting and smartypants
marked.setOptions
    highlight: (code, lang) ->
        if lang
            if lang is 'no-highlight' then code else
                hljs.highlight(lang, code).value
        else
            hljs.highlightAuto(code).value
    smartypants: true

# API server setup
app = express()
app.use express.limit('5mb')
app.use express.json()
app.set 'views', __dirname
app.set 'view engine', 'jade'

app.get '/', (req, res) ->
    res.render 'docs', {}

app.get '/test', (req, res) ->
    handleIrcMessage 'api', '#test', req.query.message
    res.end()

# Read a plugin
app.get '/plugins/:name', (req, res) ->
    type = req.query.type or 'js'
    contentType = switch type
        when 'js' then 'text/javascript'
        when 'coffee' then 'text/coffeescript'

    script = fs.readFileSync "#{__dirname}/plugins/#{req.params.name}.#{type}", 'utf-8'

    # Remove secrets
    script = script.replace /((TOKEN|SECRET)\s*=\s*)(.*)$/gm, "$1'SECRET REMOVED'"

    res.setHeader 'Content-Type', contentType
    res.send script

# Upload a new plugin
app.put '/plugins/:name', (req, res) ->
    script = req.body.script
    type = req.body.type or 'js'

    if not script
        return res.send 400, 'Script cannot be empty!'

    if type not in ['js', 'coffee']
        return res.send 400, "Unsupported script type #{type}!"

    filename = "#{req.params.name}.#{type}"

    # Save the script and setup the chroot jail
    fs.writeFileSync "#{__dirname}/plugins/#{filename}", script

    if not fs.existsSync "#{__dirname}/jails/#{filename}"
        fs.mkdirSync "#{__dirname}/jails/#{filename}"

    fs.chmodSync "#{__dirname}/jails/#{filename}", '777'

    # Run the plugin!
    if plugins[filename]
        plugins[filename].kill()
        delete plugins[filename]
    loadPlugin filename

    res.send 'ok'

# Delete and unload a plugin
app.delete '/plugins/:name', (req, res) ->
    type = req.body.type or 'js'
    filename = "#{req.params.name}.#{type}"

    fs.unlinkSync "#{__dirname}/plugins/#{filename}"
    plugins[filename].kill()
    delete plugins[filename]

    res.status(204).end()

# Fire up the server!
app.listen options.listen
console.log "Listening on port #{options.listen}"
