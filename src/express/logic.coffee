connect = require "connect"
express = require "express"
https = require "https"
http = require "http"
crypto = require "crypto"
fs = require "fs"
spew = require "spew"
gzippo = require "gzippo"

setup = (options, imports, register) ->

  # The server can act upon 404 and 500 errors, displaying an error page
  NotFound = (message) ->
    this.name = "NotFound"
    Error.call this, message
    Error.captureStackTrace this, arguments.callee

  eInternalError = (message) ->
    this.name = "InternalError"
    this.message = message
    Error.call this, message
    Error.captureStackTrace this, arguments.callee

  app = express()
  rules = []
  hasSetup = false
  sessionSecret = null
  hServ = null

  # Configured with setup
  config =
    secure: false
    secure_files: null
    port: 0

  err500path = "500.jade"
  err404path = "404.jade"

  lowRuleRegister = (rule) -> app.use (req, res, next) -> rule req, res, next

  register null,
    "line-express":

      # Register rule
      #
      # Args:
      #  rule - Function handling req, res, next
      #
      registerRule: (rule) ->
        if not hasSetup
          rules.push rule
        else spew.warning "Can't register rule after setup has been called"

      # Set 500 and 404 error view paths
      # Args:
      #  500 - path to view for 500 error
      #  404 - path to view for 404 error
      setErrorViews: (err500, err404) ->
        if err500 != undefined then err500path = err500
        if err404 != undefined then err404path = err404

      # Register page
      #
      # Args:
      #  route  - Path to page, relative to host
      #  view - Path to view
      #  args - Args passed down to the view
      #  logic  - When supplied, a callback that takes a render function
      #            that takes args as an argument. Allows for dynamic arg
      #            generation at pageload
      #
      registerPage: (route, view, args, logic) ->
        spew.info "Registered route " + route

        app.get route, (req, res) ->

          if not logic
            res.render view, args, (err, html) ->
              if err
                spew.error err
                res.status(500).render err500path, { error: err.message }
              else res.send html
          else
            logic (dynamicArgs) ->
              res.render view, dynamicArgs, (err, html) ->
                if err
                  spew.error err
                  res.status(500).render err500path, { error: err.message }
                else res.send html
            , req, res

      # Setup
      #
      # Args
      #  view_root    - Base path for views
      # static_root   - Base path for static files
      #  port     - Port number to listen on
      #  secure     - Enables/Disables HTTPS
      #  secure_files - Required for secure, an object containing paths to
      #                    key and cert
      #
      setup: (view_root, static_root, port, secure, secure_files) ->

        # Local config
        config.secure = secure
        config.secure_files = secure_files
        config.port = port

        # Generate secret
        sessionSecret = crypto
          .createHash("md5")
          .update(String(new Date().getTime()))
          .digest "base64"

        app.configure ->
          app.set "views", view_root
          app.set "view options", { layout: false }
          app.use connect.bodyParser()
          app.use express.cookieParser sessionSecret
          app.use express.session sessionSecret
          # app.use connect.static static_root
          app.use gzippo.staticGzip static_root

          # Register custom middleware
          for rule in rules
            lowRuleRegister rule

          app.use app.router
          app.use (err, req, res, next) ->
            if err instanceof NotFound
              spew.warning "Rendering 404 page for #{req.url}"
              res.status(404).render err404path, { path: req.url }
            else if err instanceof eInternalError
              spew.warning "Rendering 500 page for #{req.url}"
              res.status(500).render err500path, { error: err.message }

        hasSetup = true

        spew.init "Registered middleware, express needs initialization"

      # Throw 500
      #
      # Args
      #  msg  - Server error
      #
      throw500: (msg) -> throw eInternalError msg
      throw404: (msg) -> throw NotFound msg
      getSecret: -> return sessionSecret;
      server: app,
      httpServer: -> return hServ

      # Initialize last routes
      #
      # Called as part of the init procedure, a call to setup must precede
      initLastRoutes: ->
        if hasSetup

          # Routes
          app.get "/500", (req, res) -> throw new eInternalError ""
          app.get "/*", (req, res) -> throw new NotFound ""

          # Actually start the server
          if config.secure

            if config.secure_files.cert instanceof Array
              cert = []
              for path in config.secure_files.cert
                cert.push fs.readFileSync path
            else cert = fs.readFileSync config.secure_files.cert

            hServ = https.createServer
              key: fs.readFileSync config.secure_files.key
              cert: cert
              ca: fs.readFileSync config.secure_files.ca
            , app
            spew.init "Starting server with SSL support"
          else hServ = http.createServer app
        else spew.error "Can't perform server initialization without setup!"

      # Start server
      #
      # Called as part of init procedure, a call to setup must precede
      beginListen: ->

        if hasSetup
          hServ.listen config.port
          spew.init "Server listening on port " + config.port
        else spew.error "Can't start listening before setup!"

module.exports = setup
