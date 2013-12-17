GITHUB_TOKEN = 'your-github-oauth-token'

if not fs.existsSync '/config.json'
    fs.writeFileSync '/config.json', '{}'

config = require '/config.json'

bot.command 'github', (from, to, args) ->
    args = args.split ' '

    switch args[0]
        when 'list'
            bot.reply from, to, "Watching #{Object.keys(config).join(', ')}"
        when 'watch'
            config[args[1]] = args[2]
            fs.writeFileSync '/config.json', JSON.stringify(config)
            bot.reply from, to, "Watching #{args[1]} and reporting to #{args[2]}"
        when 'unwatch'
            delete config[args[1]]
            bot.reply from, to, "Stopped watching #{args[1]}"

bot.command 'help', (from, to, args) ->
    switch args
        when ''
            bot.reply from, to, 'github list: list watched projects\n' +
                                'github watch <project> <room>: start watching a project\n' +
                                'github unwatch <project>: stop watching a project'

# Process events for one project and report to one room
processProject = (project, room, lastCall, done) ->
    options =
        url: "https://api.github.com/repos/#{project}/events"
        headers:
            authorization: "token #{GITHUB_TOKEN}"
            'User-Agent': 'request'
        json: true

    request options, (err, res, body) =>
        if err
            bot.say room, err.toString()
            return done(err)

        for item in body
            if moment(item.created_at).isAfter lastCall
                # http://developer.github.com/v3/activity/events/types/
                switch item.type
                    when 'IssuesEvent'
                        bot.say room, "#{item.actor.login} #{item.payload.action} issue '#{item.payload.issue.title}' #{item.payload.issue.html_url}"
                    when 'IssueCommentEvent'
                        bot.say room, "#{item.actor.login} commented on '#{item.payload.issue.title}' #{item.payload.issue.html_url}"
                    when 'PullRequestEvent'
                        bot.say room, "#{item.actor.login} #{item.payload.action} pull request '#{item.payload.pull_request.title}' #{item.payload.pull_request.html_url}"
                    when 'PullRequestReviewCommentEvent'
                        bot.say room, "#{item.actor.login} commented on a pull request #{item.payload.html_url}"
                    when 'PushEvent'
                        bot.say room, "#{item.actor.login} pushed #{item.payload.size} commits to #{item.payload.ref}"
                    when 'ReleaseEvent'
                        bot.say room, "#{item.actor.login} released #{item.payload.tag_name}"

        done()

bot.interval 1000 * 60 * 3, ->
    @lastCall ?= moment()

    process = (project, done) ->
        processProject project, config[project], @lastCall, done

    async.each Object.keys(config), process, (err) ->
        # Errors are handled in the processProject function above

    @lastCall = moment()
