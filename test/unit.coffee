assert = require "assert"
mocha = require "mocha"
_ = require "underscore"
thriftPool = {_private} = require "../lib/index"
async  = require 'async'
sinon = require "sinon"
{EventEmitter} = require "events"

connection_mock = ->
  connection = new EventEmitter()
  connection.connection =
    setKeepAlive: sinon.stub()
    end: sinon.stub()
  connection

describe "thrift-pool", ->
  before ->
    @mock_connection = connection_mock()
    @thriftService =
      Client: class
        fn: ->
        fn2: ->
    @initialized_thrift_service =
      fn: sinon.stub().yields null, "xyz"
      fn2: sinon.stub().yields new Error("error"), null
    @thrift =
      createConnection: () =>
        @mock_connection.emit "connect"
        @mock_connection
      createClient: sinon.stub().returns @initialized_thrift_service
    @wrappedPool = thriftPool @thrift, @thriftService, {"host", "port"}

  it "returns an object with all the original keys of the thrift service", ->
    assert @wrappedPool.fn
    assert.equal typeof @wrappedPool.fn, "function"
    assert.deepEqual _(@wrappedPool).keys(), ["fn", "fn2"]

  it "acquires a connection from the pool when calling a method", (done) ->
    @wrappedPool.fn "foo", "bar", (err, data) =>
      assert @initialized_thrift_service.fn.calledWith "foo", "bar"
      assert.equal @thrift.createClient.args[0][0], @thriftService
      assert.equal @thrift.createClient.args[0][1], @mock_connection
      done()

  it 'returns same results that service client would', (done) ->
    async.series [
      (cb) =>
        @wrappedPool.fn "foo", (err, data) =>
          assert.equal data, "xyz"
          cb()
      (cb) =>
        @wrappedPool.fn2 "foo", (err, data) =>
          assert.notEqual err, null
          assert.equal null, data
          cb()
    ], () ->
      done()


# Makes sure create_pool properly initializes generic-pool for thrift
describe 'create_pool unit', ->
  before ->
    @mock_connection = connection_mock()
    @thrift =
      createConnection: () =>
        setImmediate => @mock_connection.emit "connect"
        @mock_connection
    @options =
      host: "host"
      port: "port"
      timeout: 250 # Timeout (in ms) for thrift.createConnection
      max_connections: 20 # Max number of connections to keep open
      min_connections: 0 # Min number of connections to keep open
      idle_timeout: 2000 # Time (in ms) to wait until closing idle connections
    @pool = _private.create_pool @thrift, @options

  # Fails if thrift connection is not properly initialized in "create:""
  it 'properly initializes thrift connection', (done) ->
    assert.equal @pool.getPoolSize(), 0
    assert.equal @pool.availableObjectsCount(), 0
    @pool.acquire (err, connection) =>
      assert.ifError err
      assert.equal connection.__ended, false
      assert.equal @pool.getPoolSize(), 1
      assert.equal @pool.availableObjectsCount(), 0
      @pool.release connection
      done()

  # Fails if thrift connection is not properly ended in "destroy:""
  it 'properly destroys a connection', (done) ->
    @pool.acquire (err, connection) =>
      assert.ifError err
      assert.equal connection.__ended, false
      prevPoolSize = @pool.getPoolSize()
      @pool.release connection
      @pool.destroy connection
      # Connection should be ended, and pool size should have 1 less
      assert.equal connection.__ended, true
      assert.equal prevPoolSize-1, @pool.getPoolSize()
      done()
