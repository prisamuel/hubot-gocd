# Description:
#   A hubot build monitor for the go continuous integration server (http://www.thoughtworks.com/products/go-continuous-delivery).
#
# Dependencies:
#   "coffee-script": ">= 1.7",
#   "xml2js": ">=0.4.4",
#   "cron": ">= 1.0.1",
#   "underscore": ">=1.6.0"
#
# Configuration:
#   HUBOT_GITHUB_EVENT_NOTIFIER_ROOM - The chatroom to write build events to
#   HUBOT_GOCI_CCTRAY_URL - The URL of the cctray.xml
#
# Commands:
#   hubot build status - Show current build status (only broken builds)
#   hubot build details - Show current status for each build pipeline
#
# Author:
#   fbernitt

cron = require('cron')
_ = require('underscore')

cctrayUrl = process.env.HUBOT_GOCI_CCTRAY_URL

if not cctrayUrl?
  console.warn("hubot-goci is not setup to fetch cctray.xml from a url (HUBOT_GOCI_CCTRAY_URL) is empty")


parser = require './util/parser'

parseData = (robot, callback) ->
  cctrayUrl = process.env.HUBOT_GOCI_CCTRAY_URL
  robot.http(cctrayUrl)
  .get() (err, res, body) ->
    if not err
      try
        projects = parser.parse_cctray(body)
        callback? projects
      catch e
        if e instanceof TypeError
          console.warn("Invalid xml data fetched from #{cctrayUrl}")
        else
          throw e
    else
      console.warn("Failed to fetch data from #{cctrayUrl}")

fetchAndCompareData = (robot, callback) ->
  parseData robot, (projects) ->
    changes = []
    for project in projects
      previous = robot.brain.data.gociProjects[project.name]
      if previous and previous.lastBuildStatus != project.lastBuildStatus
        changedStatus = if "Success" == project.lastBuildStatus then "Fixed" else "Failed"
        changes.push {"name": project.name, "type": changedStatus, "lastBuildLabel": project.lastBuildLabel}
    callback? changes

startCronJob = (robot) ->
  job = new cron.CronJob("0 */2 * * * *", ->
    fetchAndCompareData robot, (changes) ->
      room = process.env["HUBOT_GITHUB_EVENT_NOTIFIER_ROOM"]
      for change in changes
        if "Fixed" == change.type
          robot.messageRoom room, "Good news, everyone! #{change.name} is green again in ##{change.lastBuildLabel})!"
        else if "Failed" == change.type
          robot.messageRoom room, "Whoops! #{change.name} FAILED in ##{change.lastBuildLabel})!"
    updateBrain(robot)
  )
  job.start()

buildStatus = (robot, msg) ->
  failed = false
  for project in _.values(robot.brain.data.gociProjects)
    if "Failure" == project.lastBuildStatus
      failed = true
      msg.send "#{project.name}(##{project.lastBuildLabel}) is broken!"
  if not failed
    msg.send "Good news, everyone! All green!"

updateBrain = (robot) ->
  parseData robot, (projects) ->
    robot.brain.data.gociProjects[project.name] = project for project in projects


module.exports = (robot) ->
  robot.brain.data.gociProjects or= { }

  updateBrain(robot)
  startCronJob(robot)

  robot.respond /build status/i, (msg) ->
    buildStatus(robot, msg)

  robot.respond /build details/i, (msg) ->
    for project in _.values(robot.brain.data.gociProjects)
      msg.send("#{project.name}(#{project.lastBuildLabel}: #{project.lastBuildStatus}")

  updateBrain: () ->
    updateBrain(robot)


  fetchAndCompare: (callback) ->
    fetchAndCompareData robot, callback

  buildStatus: (msg) ->
    buildStatus(robot, msg)

  startCronJob: () ->
    startCronJob(robot)
