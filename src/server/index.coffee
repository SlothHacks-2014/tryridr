express = require 'express'
derby = require 'derby'
racerBrowserChannel = require 'racer-browserchannel'
liveDbMongo = require 'livedb-mongo'
coffeeify = require 'coffeeify'
MongoStore = require('connect-mongo')(express)
app = require '../app/index.coffee'
error = require './error.coffee'

expressApp = module.exports = express()


# Get Redis configuration
if process.env.REDIS_HOST
    redis = require('redis').createClient(process.env.REDIS_PORT, process.env.REDIS_HOST)
    redis.auth(process.env.REDIS_PASSWORD)
    redisObserver = require('redis').createClient(process.env.REDIS_PORT, process.env.REDIS_HOST)
    redisObserver.auth(process.env.REDIS_PASSWORD)

else if process.env.REDISCLOUD_URL
    redisUrl = require('url').parse(process.env.REDISCLOUD_URL);
    redis = require('redis').createClient(redisUrl.port, redisUrl.hostname)
    redis.auth(redisUrl.auth.split(":")[1])
    redisObserver = require('redis').createClient(redisUrl.port, redisUrl.hostname)
    redisObserver.auth(redisUrl.auth.split(":")[1])
else
    redis = require('redis').createClient()
    redisObserver = require('redis').createClient()


redis.select process.env.REDIS_DB || 1
# Get Mongo configuration 
mongoUrl = process.env.MONGO_URL || process.env.MONGOHQ_URL ||
  'mongodb://localhost:27017/project'

# The store creates models and syncs data
store = derby.createStore
  db:
    db: liveDbMongo(mongoUrl + '?auto_reconnect', safe: true)
    redis: redis
    redisObserver: redisObserver

store.on 'bundle', (browserify) ->
  # Add support for directly requiring coffeescript in browserify bundles
  browserify.transform coffeeify

createUserId = (req, res, next) ->
  model = req.getModel()
  userId = req.session.userId ||= model.id()
  model.set '_session.userId', userId
  next()

expressApp
  .use(express.favicon())
  # Gzip dynamically
  .use(express.compress())
  # Respond to requests for application script bundles
  .use(app.scripts store)
  # Serve static files from the public directory
 
  # Create static directories for assets
  .use('/fonts', express.static __dirname +  '/../../resources/fonts')
  .use('/images', express.static __dirname +  '/../../resources/images')
  .use('/scripts', express.static __dirname +  '/../../resources/scripts')
  # Add browserchannel client-side scripts to model bundles created by store,
  # and return middleware for responding to remote client messages
  .use(racerBrowserChannel store)
  # Add req.getModel() method
  .use(store.modelMiddleware())

  # Parse form data
  # .use(express.bodyParser())
  # .use(express.methodOverride())

  # Session middleware
  .use(express.cookieParser())
  .use(express.session
    secret: process.env.SESSION_SECRET || 'YOUR SECRET HERE'
    store: new MongoStore(url: mongoUrl, safe: true)
  )
  .use(createUserId)

 
model = store.createModel()


# SERVER-SIDE ROUTES #

#expressApp.use (req, res, next) ->
# host = process.env.NEW_BASE_URL || 'localhost'

# if req.host != host
#   res.redirect ('http://' + process.env.NEW_BASE_URL + req.url)
  
# else
#   next()

# Create an express middleware from the app's routes
expressApp.use(app.router())
expressApp.use(expressApp.router)
expressApp.use(error()) 

location = (lat, long) ->
  return 'zones' + lat + long + '.value'

expressApp.get '/zones/:lat/:long', (req, res, next) ->
   model.subscribe location(req.params.lat, req.params.long), ->
     res.json { value: model.get(location(req.params.lat, req.params.long)) }

expressApp.get '/zones/:lat/:long/:level', (req, res, next) ->
  model.subscribe location(req.params.lat, req.params.long), ->
    model.set(location(req.params.lat, req.params.long), req.params.level)
    res.send()

expressApp.all '*', (req, res, next) ->
  next '404: ' + req.url

