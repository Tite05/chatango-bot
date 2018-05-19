#author agunq 
#contact: <agunq.e@gmail.com>
#file ct.rb
#Require Ruby 2.0
#Require Websocket [gem install webscoket]

require 'socket'
require 'uri'
require 'net/http'
require 'websocket'

##################################################
$debug = false

$Channels = {
  "white" => 0,
  "red" => 256,
  "blue" => 2048,
  "shield" => 64,
  "staff" => 128,
  "mod" => 32768
  #"mod" => 32780
}

class WebSocketClient
  
  def connect(url, options={})
    return if @socket
    @url = url
    uri = URI.parse url
    @socket = TCPSocket.new(uri.host, uri.port)
    @handshake = ::WebSocket::Handshake::Client.new :url => url, :headers => options[:headers]
    @handshaked = false
    @pipe_broken = false
    @frame = ::WebSocket::Frame::Incoming::Client.new
    @closed = false
    @socket.write @handshake.to_s
    while !@handshaked do
      begin
        unless @recv_data = @socket.getc
          next
        end
        unless @handshaked
          @handshake << @recv_data
          if @handshake.finished?
            @handshaked = true
          end
        end
      rescue Exception => e
        puts "handshake fail - #{e.message}"
        @handshaked = true
        self.close
      end
    end
  end

  def socket
    return @socket
  end

  def send(data, options={:type => :text})
    return if !@handshaked or @closed
    type = options[:type]
    frame = ::WebSocket::Frame::Outgoing::Client.new(:data => data, :type => type, :version => @handshake.version)
    begin
      @socket.write(frame.to_s)
    rescue Exception => e
      @pipe_broken = true
      puts "pipe broken - #{e.message}"
      self.close
    end
  end

  def read
    begin
      @recv_data = @socket.recv(1024)
      @frame << @recv_data.to_s
      return @frame
    rescue Exception => e
      puts "frame error - #{e.message}"
      self.close
    end
  end

  def close
    return if @closed
    if !@pipe_broken
      send(nil, :type => :close)
    end
    @closed = true
    @socket.close if @socket
    @socket = nil
  end

  def open?
    !@closed
  end
end

################################################################
# Tagserver stuff
################################################################
def getServer(group)
  tsweights = [
    ['5',   75], ['6',   75], ['7',   75], ['8',   75], ['16',  75],
    ['17',  75], ['18',  75], ['9',   95], ['11',  95], ['12',  95],
    ['13',  95], ['14',  95], ['15',  95], ['19', 110], ['23', 110],
    ['24', 110], ['25', 110], ['26', 110], ['28', 104], ['29', 104],
    ['30', 104], ['31', 104], ['32', 104], ['33', 104], ['35', 101],
    ['36', 101], ['37', 101], ['38', 101], ['39', 101], ['40', 101],
    ['41', 101], ['42', 101], ['43', 101], ['44', 101], ['45', 101],
    ['46', 101], ['47', 101], ['48', 101], ['49', 101], ['50', 101],
    ['52', 110], ['53', 110], ['55', 110], ['57', 110], ['58', 110],
    ['59', 110], ['60', 110], ['61', 110], ['62', 110], ['63', 110],
    ['64', 110], ['65', 110], ['66', 110], ['68',  95], ['71', 116],
    ['72', 116], ['73', 116], ['74', 116], ['75', 116], ['76', 116],
    ['77', 116], ['78', 116], ['79', 116], ['80', 116], ['81', 116],
    ['82', 116], ['83', 116], ['84', 116]
  ]
  
  group = group.gsub("_", "q")
  group = group.gsub("-", "q")
  fnv = group[0, [5, group.length].min].to_i(base=36).to_f
  lnv = group[6, [3, (group.length - 5)].min]
  if lnv
    lnv = lnv.to_i(base=36).to_f
    lnv = [lnv, 1000].max
  else
    lnv = 1000
  end
  num = (fnv % lnv) / lnv
  maxnum = tsweights.map{|x| x[1]}.inject { |sum, x| sum + x }
  cumfreq = 0
  sn = 0
  for wgt in tsweights    
    cumfreq += (wgt[1].to_f / maxnum)
    if(num <= cumfreq)
      sn = wgt[0].to_i
      break
    end
  end
  return "s" + sn.to_s + ".chatango.com"
end

################################################################
# Uid
################################################################
def genUid
  return rand(10 ** 15 .. 10 ** 16).to_s
end

################################################################
# Message stuff
################################################################
def clean_message(text)
  c = text.match("<n(.*?)\/>")
  f = text.match("<f(.*?)>")
  if c
    c = c.captures[0]
  end
  if f 
    f = f.captures[0]
  end
  text = text.sub("<n.*?/>", "")
  text = text.sub("<f.*?>", "")
  text = strip_html(text)
  text = text.gsub("&lt;", "<")
  text = text.gsub("&gt;", ">")
  text = text.gsub("&quot;", "\"")
  text = text.gsub("&apos;", "'")
  text = text.gsub("&amp;", "&")
  return text, c, f
end

def strip_html(msg)
  msg = msg.gsub(/<\/?[^>]*>/, "")
  return msg
end

def parseFont(f)
  if f != nil
    sizecolor, fontface = f.split("=", 1)
    sizecolor = sizecolor.strip()
    size = sizecolor[1,3].to_i
    col = sizecolor[3,3]
    if col == ""
      col = nil
    end
    face = f.split("\"", 2)[1].split("\"", 2)[0]
    return col, face, size
  else
    return nil, nil, nil
  end
end 

################################################################
# Anon id
################################################################
def getAnonId(n, id) 
  if n == nil; n = "5504"; end
  j = n.split("").map{|x| x.to_i}
  k = id[4,id.length].split("").map{|x| x.to_i}
  l = j.zip(k)
  m = l.map{|x| (x[0] + x[1]).to_s[-1]}
  return m.join("")
end

class Task_

  attr_accessor :mgr, :target, :evt, :isInterval, :args, :timeout

  def initialize(mgr, timeout, isInterval, evt, args)
    @mgr = mgr
    @target = Time.now.to_f + timeout
    @evt = evt
    @isInterval = isInterval
    @args = args
    @timeout = timeout
  end
  
  def newtarget
    @target = Time.now.to_f + timeout
  end
 
  def inspect
    return "<Task: #{target}>"
  end
end

################################################################
# User class
################################################################
$users = {}
def User(name)
  if name == nil; name = ""; end
  capser = name
  name = name.downcase
  if not $users.include?(name)
    user = User_.new(name)
    $users[name] = user
  else
    user = $users[name.downcase]
  end
  user.capser = capser
  return user
end

class User_

  attr_accessor :name, :puid, :nameColor, :fontSize, :fontFace, :fontColor, :mbg, :mrec

  ####
  # Initialize
  ####
  def initialize(name)
    @name = name.downcase
    if name and not name[0].include?("#!")
      capser = name
    else
      capser = name[1, name.length]
    end
    @capser = capser 
    @puid = nil
    @nameColor = "000"
    @fontSize = 12
    @fontFace = "0"
    @fontColor = "000"
    @mbg = false
    @mrec = false
  end

  ####
  # Properties
  ####
  def name; return @name; end
  def capser; return @capser; end
  def capser=(val); @capser = val; end
  def fontColor; return @fontColor; end
  def fontFace; return @fontFace; end
  def fontSize; return @fontSize; end
  def nameColor; return @nameColor; end

  def inspect
    return "<User: #{name}>"
  end

  def to_s
    return "<User: #{name}>"
  end
end

################################################################
# Message class
################################################################
class Message
  
  attr_accessor :user, :body, :msgid, :sid, :unid, :room, :ip, :time, :nameColor, :fontColor, :fontFace, :fontSize, :channel, :badge

  ####
  # Initialize
  ####
  def initialize(room, user, body, msgunid, msgsid, ip, mtime, mnameColor, mfontColor, mfontFace, mfontSize)
    @user = user
    @body = body
    @msgid = ""
    @unid = msgunid
    @sid = msgsid
    @room = room
    @ip = ip
    @time = mtime
    @nameColor = mnameColor
    @fontColor = mfontColor
    @fontFace = mfontFace
    @fontSize = mfontSize
    @channel = channel
    @channel = badge
  end
  
  def attach(room, msgid)
    @msgid = msgid
    @room = room
  end
  
  def detach(room, msgid)
    @msgid = msgid
    @room = room
  end

  ####
  # Properties
  ####
  def id; return @msgid; end
  def time; return @time; end
  def user; return @user; end
  def body; return @body; end
  def ip; return @ip; end
  def fontColor; return @fontColor; end
  def fontFace; return @fontFace; end
  def fontSize; return @fontSize; end
  def nameColor; return @nameColor; end
  def channel; return @channel; end
  def badge; return @badge; end
  def unid; return @unid; end
  
  ####
  # (?)
  ####
  def inspect
    return "<Message: #{user}>"
  end
end

################################################################
# PM class
################################################################
class PM
  ####
  # Initialize
  ####
  def initialize(mgr)
    @auid = nil
    @server = "c1.chatango.com"
    @connected = false
    @firstCommand = true
    @mgr = mgr
    @blocklist = {}
    @contacts = {}
    @socket = WebSocketClient.new
  end

  ####
  # Connections
  ####
  def connect
    headers = { "Origin" => "http://st.chatango.com", "Pragma" => "no-cache", "Cache-Control" => "no-cache" }
    @socket.connect("ws://#{@server}:8080", options = {:headers => headers})
    auth
    @firstCommand = true
    @connected = true
    setInterval(20, :ping, "Ping! at <PM>")
  end

  def auth
    if @mgr.username != nil and @mgr.password != nil
      uri = URI('http://chatango.com/login')
      params = {
        "user_id" => @mgr.username,
        "password" => @mgr.password,
        "storecookie" => "on",
        "checkerrors" => "yes"
        }
      uri.query = URI.encode_www_form(params)
      res = Net::HTTP.get_response(uri)
      cookie = res['set-cookie'].match("auth\.chatango\.com ?= ?([^;]*)").captures
      if cookie
        @auid = cookie[0]
      end
      sendCommand("tlogin", @auid.to_s, 2)
    end
  end

  def disconnect
    if @connected == true
      if @socket.open? == true
        @socket.close   
      end
      @connected = false
    end
    callEvent(:onPMDisconnect, self)
  end

  ####
  # Feed/process
  ####
  def process(data)
    if data
      data = data.split("\x00")
      for d in data
        food = d.split(":")
        if food.length > 0
          cmd = "rcmd_" + food[0]
          if self.respond_to?(cmd)
            self.send(cmd, food)
          elsif $debug
            puts("unknown data: " + data.to_s)
          end
        end
      end
    end
  end 

  ####
  # Properties
  ####
  def socket; return @socket; end
  def connected; return @connected; end
  def contacts; return @contacts; end
  def blocklist; return @blocklist; end

  ####
  # Received Commands
  ####
  def rcmd_OK(args)
    sendCommand("wl")
    sendCommand("getblock")
    callEvent(:onPMConnect, self)
  end

  def rcmd_block_list(args)
    @blocklist = {}
    for name in args
    #  next if name == ""; end
      @blocklist[name] = User(name)
    end
  end

  def rcmd_DENIED(args)
    disconnect
    callEvent(:onLoginFail)
  end

  def rcmd_msg(args)
    user = User(args[1])
    body = strip_html(args[6, args.length].join(":"))
    body = body[0, body.length-2]
    callEvent(:onPMMessage, self, user, body)
  end

  def rcmd_msgoff(args)
    user = User(args[1])
    body = strip_html(args[6, args.length].join ":")
    body = body[0, body.length-2]
    callEvent(:onPMOfflineMessage, self, user, body)
  end

  def rcmd_kickingoff(args)
    disconnect
  end 

  def rcmd_toofast(args)
    disconnect
  end

  def rcmd_unblocked(user)
    if user.include?(@blocklist)
      @blocklist.delete(user)
      callEvent(:onPMUnblock, self, user)
    end
  end

  ####
  # Commands
  ####
  def ping(h)
    # send a ping
    sendCommand("")
    callEvent(:onPMPing, self)
  end
  
  def message(user, msg)
    # send a pm to a user
    if msg != nil
      sendCommand("msg", user.to_s, "<n7/><m v='1'>#{msg}</m>")
    end
  end

  def addContact(user)
    unless user.include?(@contacts)
      sendCommand("wlaad", user.name.to_s)
      @contacts[user] = user
      callEvent(:onPMContactAdd, self, user)
    end
  end

  def removeContact(user)
    if user.include?(@contacts)
      sendCommand("wldelete", user.name.to_s)
      @contacts.delete(user)
      callEvent(:onPMContactRemove, self, user)
    end
  end

  def block(user)
    unless @blocklist.include?(user)
      sendCommand("block", user.name.to_s, user.name.to_s, "S")
      @blocklist[user] = user
      callEvent(:onPMBlock, self, user)
    end
  end

  def unblock(user)
    if @blocklist.include?(user)
      sendCommand("unblock", user.name.to_s)
    end
  end

  ####
  # Util
  ####
  def callEvent(evt, *args)
    if @mgr.respond_to?(evt)
      @mgr.send(evt, *args)
    end
  end

  def sendCommand(*args)
    # Send a command.
    if @firstCommand == true
      terminator = "\x00"
      @firstCommand = false
    else
      terminator = "\r\n\x00"
    end
    @socket.send(args.join(":").encode + terminator)
  end

  def setInterval(timeout, evt, *args)
    task = Task_.new(self, timeout, true, evt, *args)
    @mgr.add_task task
  end
   
  def setTimeout(timeout, evt, *args)
    task = Task_.new(self, timeout, false, evt, *args)
    @mgr.add_task task
  end

  def inspect
    return "<PM: #{@mgr.user}>"
  end
end 

################################################################
# Room class
################################################################
class Room
  ####
  # Init
  ####
  def initialize(mgr, room)
    @name = room
    @uid = genUid
    @server = getServer(room)
    @connected = false
    @reconnecting = false
    @mgr = mgr
    @currentname = nil
    @botname = nil
    @firstCommand = true
    @mqueue = nil
    @mods = []
    @owner = nil
    @socket = WebSocketClient.new
    @channel = 0
    @badge = 0
    @status = {}
  end
  
  ####
  # Connect/disconnect
  ####
  def connect
    # Connect to the server.
    @firstCommand = true
    headers = {
      "Origin" => "http://st.chatango.com",
      "Pragma" => "no-cache",
      "Cache-Control" => "no-cache"}
    @socket.connect("ws://#{@server}:8080", options = {:headers => headers})
    auth
    @connected = true
    setInterval(20, :ping, "Ping! at #{@name}")
  end

  def reconnect
    # Reconnect.
    @reconnecting = true
    if @connected == true
      disconnect
    end
    @uid = genUid
    connect
    @reconnecting = false
  end

  def disconnect
    # Disconnect from the server.
    if @connected == true
      if @socket.open? == true
        @socket.close   
      end
      @connected = false
      callEvent(:onDisconnect, self)
    end
  end

  def auth
    # Authenticate.
    if @mgr.username != nil and @mgr.password != nil
      sendCommand("bauth", @name.to_s, @uid.to_s, @mgr.username.to_s, @mgr.password.to_s)
      @currentname = @mgr.username
    # login as anon
    else
      sendCommand("bauth", @name.to_s, @uid.to_s)
    end
  end

  ####
  # Properties
  ####
  def name; return @name; end
  def userlist; return @status.values; end
  def channel; return @channel; end
  def channel=(val); @channel = val; end
  def badge; return @badge; end
  def badge=(val); @badge = val; end
  def owner; return @owner; end
  def ownername; return @owner.name; end
  def modnames; return @mods; end
  def socket; return @socket; end
  def connected; return @connected; end

  ####
  # Feed/process
  ####
  def process(data)
    # Process a command string.
    if data
      data = data.split("\x00")
      for d in data
        food = d.split(":")
        if food.length > 0
          cmd = "rcmd_" + food[0]
          if self.respond_to?(cmd)
            self.send(cmd, food)
          elsif $debug
            puts("unknown data: " + data.to_s)
          end
        end
      end
    end
  end 

  ####
  # Received Commands
  ####
  def rcmd_ok(args)
    puts(args)
    if args[3] == "C" and @mgr.username == nil and @mgr.password == nil
      n = args[5].split('.')[0]
      n = n[-4, n.length]
      aid = args[2][0, 8]
      pid = "!anon" + getAnonId(n, aid)
      @currentname = pid
      @mgr.user.setNameColor(n)
    elsif args[3] == "C" and @mgr.password == nil
      @currentname = @mgr.username
      sendCommand("blogin", @mgr.username.to_s)
    end
    @owner = User(args[1])
    #@mods = [lambda { |x| User(x.split(",")[0], args[7].split(";") }]
  end
  
  def rcmd_denied(args)
    disconnect
    callEvent(:onConnectFail, self)
  end

  def rcmd_inited(args)
    sendCommand("g_participants", "start")
    sendCommand("getpremium", "1")
    callEvent(:onConnect, self)
  end

  def rcmd_(args)
    callEvent(:onPong, self)
  end

  def rcmd_premium(args)
    if args[2].to_i > Time.now.to_i
      @premium = true
      if @mgr.user.mbg
        self.setBgMode(1)
      end
      if @mgr.user.mrec
        self.setRecordingMode(1)
      end
    else
    @premium = false
    end
  end

  def rcmd_b(args) 
    name = args[2]
    msg = args[10, args.length].join(":")
    msg, n, f = clean_message(msg)
    
    if name == ""
      nameColor = nil
      name = "#" + args[3]
      if name == "#"
        name = "!anon" + getAnonId(n, args[4])
      end
    else
      if n
        nameColor = n
      else 
        nameColor = nil
      end
    end 
    user = User(name)
    fontColor, fontFace, fontSize = parseFont(f)
    mtime = args[1].to_f
    msg = Message.new(self, user, msg, args[5], args[6], args[7], mtime, nameColor, fontColor, fontFace, fontSize)
    @mqueue  = msg
  end

  def rcmd_u(args)
    if @mqueue
      msg = @mqueue 
      if msg.sid == args[1]
        msg.attach(self, args[2])
        if msg.user != @mgr.user
          msg.user.fontColor = msg.fontColor
          msg.user.fontFace = msg.fontFace
          msg.user.fontSize = msg.fontSize
          msg.user.nameColor = msg.nameColor
        end
        @mqueue = nil
        callEvent(:onMessage, self, msg.user, msg)
      end
    end
  end

  def rcmd_g_participants(args)
    args = args[1, args.length - 1].join(":")
    args = args.split(";")
    for data in args
      data = data.split(":")
      sid = data[0]
      puid = data[2]
      name = data[3]
      if name == "None"
        n = data[1].to_i.to_s[-4, 4]
        if data[4] == "None"
          name = "!anon" + getAnonId(n, puid)
        end
      end
      user = User name
      user.puid = puid
      @status[sid] = user
    end
  end
  
  def rcmd_participant(args)
    args = args[1, args.length - 1]
    sid = args[1]
    puid = args[2]
    name = args[3]
    if name == "None"
      n = args[6].to_i.to_s[-4, 4]
      if args[4] == "None"
        name = "!anon" + getAnonId(n, puid)
      end
    end
    user = User(name)
    user.puid = puid
    #leave
    if args[0] == "0" 
      if @status.key?(sid)
        @status.delete(sid)
        callEvent(:onLeave, self, user)
      end
    end
    #join/rejoin
    if args[0] == "1" or args[0] == "2"
      @status[sid] = user
      callEvent(:onJoin, self, user)
    end
  end

  def rcmd_updateprofile(args)
    user = User(args[1])
    callEvent(:onUpdateProfile, self, user)
  end

  def rcmd_show_fw(args)
    callEvent(:onFloodWarning, self)
  end

  def rcmd_show_tb(args)
    callEvent(:onFloodBan, self)
  end

  def rcmd_tb(args)
    callEvent(:onFloodBanRepeat, self)
  end

  ####
  # Commands
  ####
  def login(name, pass=nil)
    if pass != nil
      sendCommand("blogin", name.to_s, pass.to_s)
    else
      sendCommand("blogin", name.to_s)
    end
    @currentname = name
  end

  def logout
    sendCommand("blogout")
    @currentname = @botname
  end
  
  def ping(h)
    sendCommand("")
    callEvent(:onPing, self)
  end

  def message(msg, html=false, channel=nil, badge=nil)
    # Send a message. (Use "\n" for new line)
    if channel == nil
      channel = @channel
    end
    if badge == nil
      badge = @badge
    end
    if channel < 4
      _channel = (((channel & 2) << 2 | (channel & 1)) << 8)
    elsif channel == 4
      _channel = 32768
    end
    _badge = badge * 64
    if html == false
      msg = msg.gsub("<", "&lt;")
      msg = msg.gsub(">", "&gt;")
    end
    if msg.include?("\n")
      msg = msg.gsub("\n","\r")
    end
    msgs = msg.chars.each_slice(2000).map(&:join)
    s, c, f = @mgr.user.fontSize, @mgr.user.fontColor, @mgr.user.fontFace
    for msg in msgs
      msg = "<n#{@mgr.user.nameColor}/><f x#{s}#{c}=\"#{f}\">#{msg}</f>"
      if _channel != nil and _badge != nil
        sendCommand("bm", "ibrs", _channel.to_s+_badge.to_s, msg.to_s)
      else
        sendCommand("bmsg", "t12r", msg.to_s)
      end
    end
  end

  def setBgMode(mode)
    # turn on/off bg
    sendCommand("msgbg", mode.to_s)
  end
  
  def setRecordingMode(mode)
    # turn on/off rcecording
    sendCommand("msgmedia", mode.to_s)
  end

  def addMod(user)
    # Add a moderator.
    if getLevel(User(username)) == 2
      sendCommand("addmod", user.name.to_s)
    end
  end

  def removeMod(user)
    # Remove a moderator.
    if getLevel(User(username)) == 2
      sendCommand("removemod", user.name.to_s)
    end
  end

  def clearall
    # Clear all messages. (Owner only)
    if getLevel(username) != 0
      sendCommand("clearall")
      sendCommand("getannouncement")
      @clearing_all = true
    end
  end

  def rawBan(name, ip, unid)
    sendCommand("block", unid.to_s, ip.to_s, name.to_s)
  end

  def ban(msg)
    # Ban a message's sender. (Moderator only)
    if getLevel(@username) > 0
      rawBan(msg.user.name, msg.ip, msg.unid)
    end
  end

  def requestBanList
    # Request an updated banlist
    sendCommand("blocklist", "block", "", "next", "500")
  end

  def requestUnBanList
    # Request an updated banlist.
    sendCommand("blocklist", "unblock", "", "next", "500")
  end

  ####
  # Util
  ####
  def sendCommand(*args)
    # Send a command.
    if @firstCommand == true
      terminator = "\x00"
      @firstCommand = false
    else
      terminator = "\r\n\x00"
    end
    @socket.send(args.join(":").encode + terminator)
  end

  def callEvent(evt, *args)
    if @mgr.respond_to?(evt)
      @mgr.send(evt, *args)
    end
  end

  def getLevel(user)
    # get the level of user in a room
    if user == @owner
      return 2
    end
    if @modnames.include?(user)
      return 1
    end
    return 0
  end

  def setInterval(timeout, evt, *args)
    # Call a function at least every timeout seconds with specified arguments.
    task = Task_.new(self, timeout, true, evt, *args)
    @mgr.add_task(task)
  end
  
  def setTimeout(timeout, evt, *args)
    # Call a function after at least timeout seconds with specified arguments.
    task = Task_.new(self, timeout, false, evt, *args)
    @mgr.add_task(task)
  end
  
  def inspect
    return "<Room: #{name}>"
  end
end 

################################################################
# Chatango class
################################################################
class Chatango # RoomManager (?)
  ####
  # Initialize
  ####
  def initialize
    @rooms = {}
    @user = nil
    @username = nil
    @password = nil
    @tasks = []
    @running = false
    @pm = nil
  end

  ####
  # Join/leave
  ####
  def joinRoom(room)
    # Join a room or return None if already joined.
    room = room.downcase
    if @rooms.key?(room) == false
      @rooms[room] = Room.new(self, room)
      @rooms[room].connect
    elsif @rooms.key?(room) == true
      if @rooms[room].connected == false
        @rooms[room].connect
      end
    end
  end
  
  def leaveRoom(room)
    # Leave a room.
    room = room.downcase
    if @rooms.key?(room) == true
      @rooms[room].disconnect
      @rooms.delete(room)
      return true
    else
      return nil
    end
  end

  def getRoom(room)
    # Get room with a name, or None if not connected to this room.
    room = room.downcase
    if @rooms.key?(room) == true
      return @rooms[room]
    else
      return nil
    end
  end

  ####
  # Properties
  ####
  def user; return User(@username); end
  def username; return @username; end
  def name; return @username; end
  def password; return @password; end
  def pm; return @pm; end
  def rooms
    rl = []
    ro = @rooms.values
    for r in ro
      if r.connected == true
        rl << r
      end
    end
    return rl
  end

  ####
  # Virtual methods
  ####
  def onInitialize
    # Called on initialize.
  end

  def onConnect(room)
    # Called when connected to the room.
  end
  
  def onReconnect(room)
    # Called when reconnected to the room.
  end

  def onConnectFail(room)
    # Called when the connection failed.
  end

  def onDisconnect(room)
    # Called when the client gets disconnected.
  end

  def onLoginFail(room)
    # Called on login failure, disconnects after.
  end

  def onFloodBan(room)
    # Called when either flood banned or flagged.
  end

  def onFloodBanRepeat(room)
    # Called when trying to send something when floodbanned.
  end

  def onFloddWarning(room)
    # Called when an overflow warning gets received.
  end

  def onMessage(room, user, message)
    # Called when a message gets received.
  end

  def onJoin(room, user)
    # Called when a user joins. Anonymous users get ignored here.
  end
  
  def onLeave(room, user)
    # Called when a user leaves. Anonymous users get ignored here.
  end

  def onPing(room)
    # Called when a ping gets sent.
  end

  def onPong(room)
    # Called when a pong it's received.
  end

  def onUpdateProfile(room, user)
    # 
  end

  def onPMConnect(pm)
    # Called when connected to the pm
  end

  def onPMDisconnect(pm)
    # Called when disconnected from the pm
  end

  def onPMPing(pm)
    # Called when sending a ping to the pm
  end

  def onPMMessage(pm, user, body)
    # Called when a message is received
  end

  def onPMOfflineMessage(pm, user, body)
    # Called when connected if a message is received while offline
  end

  def onPMContactAdd(pm, user)
    # Called when the contact added message is received
  end

  def onPMContactRemove(pm, user)
    # Called when the contact remove message is received
  end

  ####
  # Main
  ####
  def main
    onInitialize
    while @running == true
      begin
        sockets = @rooms.values.collect{|k| k.socket.socket }
        connections = @rooms.values
        if @pm != nil
          sockets << @pm.socket.socket
          connections << @pm
        end
        sockets = sockets.reject{|k| k == nil}
        w, r, e = select(sockets, nil, nil, 0)
        for c in connections
          if c.socket.open? == false
            c.disconnect
          elsif w != nil
            for socket in w  
              if c.socket.socket == socket  
                frame = c.socket.read
                while partial_data = frame.next
                  partial_data = partial_data.to_s.force_encoding("utf-8").encode
                  c.process(partial_data)
                end              
              end          
            end
          end
        end
      rescue Exception => e  
        puts e.message
        puts e.backtrace
      end
      ticking
    end
  end

  def start(rooms=[], username=nil, password=nil)
    @username = username
    @password = password
    @running = true
    if rooms.length == 0
      print("Room names separated by semicolons: ")
      room = gets.chomp
      rooms = room.split(";")
    end
    if username == nil or username == ""
      print("User Name: ")
      @username = gets.chomp
    end
    if @username == "" 
      @username = nil
    end
    if password == nil or password == ""
      print("Password: ")
      @password = gets.chomp
    end
    if @password == ""
      @password = nil
    end
    if @username != nil and @password != nil
      @pm = PM.new(self)
      @pm.connect
    end
    for room in rooms
      joinRoom(room)
    end
    main
  end

  def finish
    @tasks.clear
    for name in @rooms.keys 
      leaveRoom(name)
    end
    if @pm != nil
      @pm.disconnect
    end
    @running = false
  end

  ####
  # Commands
  ####
  def enableBg
    # Enable background if available.
    self.user.mbg = true
    for room in rooms
      room.setBgMode(1)
    end
  end
  
  def disableBg
    # Disable background.
    self.user.mbg = false
    for room in rooms
      room.setBgMode(0)
    end
  end

  def enableRecording
    # Enable recording if available.
    self.user.mrec = true
    for room in rooms
      room.setRecordingMode(1)
    end
  end
  
  def disableRecording
    # Disable recording.
    self.user.mrec = false
    for room in rooms
      room.setRecordingMode(0)
    end
  end

  def setNameColor(color)
    # Set name color.
    self.user.nameColor = color
  end
  
  def setFontColor(color)
    # Set font color.
    self.user.fontColor = color
  end

  def setFontFace(face)
    # Set font face/family.
    self.user.fontFace = face
  end

  def setFontSize(size)
    # Set font size.
    self.user.fontSize = size
  end

  ####
  # Util
  ####
  def callEvent(evt, *args)
    if self.respond_to?(evt)
      self.send(evt, *args)
    end
  end

  def setInterval(timeout, evt, *args)
    # Call a function at least every timeout seconds with specified arguments.
    task = Task_.new(self, timeout, true, evt, *args)
    @mgr.add_task(task)
  end
  
  def setTimeout(timeout, evt, *args)
    # Call a function after at least timeout seconds with specified arguments.
    task = Task_.new(self, timeout, false, evt, *args)
    @mgr.add_task(task)
  end

  def add_task(newtask)
    @tasks << newtask
  end

  def removeTask(task)
    # Cancel a task.
    if @tasks.include?(task)
      @tasks.delete(task)
    end
  end
  
  def tasks
    tk = []
    for t in @tasks
      if t.mgr.connected == true
        tk << t
      end
    end
    return tk
  end
    
  def ticking
    now = Time.now.to_f
    if tasks.length > 0
      for task in tasks
        if task.target <= now
          if task.mgr.respond_to?(task.evt)
            task.mgr.send(task.evt, task.args)
            if task.isInterval
              new = task.timeout + now
              task.newtarget
            else
              @tasks.delete(task)
              task = nil
            end
          end
        end
      end
    end
  end
  
  def inspect
    return "<Chatango: #{username}>"
  end
end
