bot.command 'help', (from, to, args) ->
    switch args
        when ''
            bot.reply from, to, 'echo [message]: say a message back to you'
        when 'echo'
            bot.reply from, to, 'Echo a message back to the sender or channel\n' +
                                "Example: #{bot.name} echo hello"

bot.command 'echo', (from, to, args) ->
    bot.reply from, to, args
