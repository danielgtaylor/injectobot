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
loadPlugin = (name, filename) ->
    console.log "Loading plugin #{name} from #{filename}"
    child = child_process.fork "#{__dirname}/runner.coffee", [USERNAME, filename, options.user]
    child.filename = filename
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
for filename in fs.readdirSync("#{__dirname}/plugins")
    loadPlugin filename.split('.')[0...-1].join('.'), filename

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

# Middleware to limit upload size and save request body
app.use (req, res, next) ->
    len = 0
    raw = ''
    req.setEncoding 'utf-8'
    req.on 'data', (chunk) ->
        # Length check - limit to 5mb max upload
        len += chunk.length
        if len > 5242880
            req.destroy()
        raw += chunk
    req.on 'end', ->
        req.body = raw
        next()

# Setup template engine for docs
app.set 'views', __dirname
app.set 'view engine', 'jade'

app.get '/', (req, res) ->
    res.render 'docs',
        host: os.hostname()
        port: options.listen

app.get '/test', (req, res) ->
    handleIrcMessage 'api', '#test', req.query.message
    res.end()

# Get a list of all plugins
app.get '/plugins', (req, res) ->
    res.send (name for name of plugins)

# Read a plugin
app.get '/plugins/:name', (req, res) ->
    name = req.params.name
    filename = null

    for ext in ['js', 'coffee']
        path = "#{__dirname}/plugins/#{name}.#{ext}"
        if fs.existsSync path
            filename = path
            contentType = switch ext
                when 'js' then 'application/javascript'
                when 'coffee' then 'application/coffeescript'
            break

    if not filename then return res.send 404

    script = fs.readFileSync filename, 'utf-8'

    # Remove secrets
    script = script.replace /((TOKEN|SECRET)\s*=\s*)(.*)$/gm, "$1'SECRET REMOVED'"

    res.setHeader 'Content-Type', contentType
    res.send script

# Upload a new plugin
app.put '/plugins/:name', (req, res) ->
    name = req.params.name
    script = req.body
    type = switch req.header 'content-type'
        when 'application/javascript' then 'js'
        when 'application/coffeescript' then 'coffee'

    if not type then return res.send 400, 'Invalid content type! Must be application/javascript or application/coffeescript!'

    if not script
        return res.send 400, 'Script cannot be empty!'

    # Remove existing scripts
    if plugins[name]
        plugins[name].kill()
        delete plugins[name]

    for ext in ['js', 'coffee']
        path = "#{__dirname}/plugins/#{name}.#{ext}"
        if fs.existsSync path then fs.unlinkSync path

    filename = "#{name}.#{type}"

    if not fs.existsSync "#{__dirname}/plugins"
        fs.mkdirSync "#{__dirname}/plugins"

    # Save the script and setup the chroot jail
    fs.writeFileSync "#{__dirname}/plugins/#{filename}", script

    if not fs.existsSync "#{__dirname}/jails"
        fs.mkdirSync "#{__dirname}/jails"

    if not fs.existsSync "#{__dirname}/jails/#{name}"
        fs.mkdirSync "#{__dirname}/jails/#{name}"

    fs.chmodSync "#{__dirname}/jails/#{name}", '777'

    # Run the plugin!
    loadPlugin name, filename

    res.send 'ok'

# Delete and unload a plugin
app.delete '/plugins/:name', (req, res) ->
    name = req.params.name

    for ext in ['js', 'coffee']
        path = "#{__dirname}/plugins/#{name}.#{ext}"
        if fs.existsSync path then fs.unlinkSync path

    plugins[name].kill()
    delete plugins[name]

    res.status(204).end()

# Fire up the server!
app.listen options.listen
console.log "Listening on port #{options.listen}"
