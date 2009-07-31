require 'socket'
require 'thread'

# = D-Bus main module
#
# Module containing all the D-Bus modules and classes.
module DBus
  # D-Bus main connection class
  #
  # Main class that maintains a connection to a bus and can handle incoming
  # and outgoing messages.
  class Connection
    # The unique name (by specification) of the message.
    attr_reader :unique_name
    # The socket that is used to connect with the bus.
    #attr_reader :socket

    # Create a new connection to the bus for a given connect _path_. _path_
    # format is described in the D-Bus specification:
      # http://dbus.freedesktop.org/doc/dbus-specification.html#addresses
    # and is something like:
    # "transport1:key1=value1,key2=value2;transport2:key1=value1,key2=value2"
    # e.g. "unix:path=/tmp/dbus-test" or "tcp:host=localhost,port=2687"
    def initialize(path)
      #dlog "new connection initialized: #{path}"
      @path = path
      @unique_name = nil
      @buffer = ""
      @method_call_replies = Hash.new
      @method_call_msgs = Hash.new
      @signal_matchrules = Array.new
      @proxy = nil
      @object_root = Node.new("/")
      @shared_socket = nil
      @is_tcp = false
      @mutex = Mutex.new #used to synchronize shared ressource access
      @update_mutex = Mutex.new #for synchronizing the update_buffer method
    end

    #trying to make socket access thread safe
    def socket
      @mutex.synchronize { return @shared_socket }
    end

    # Connect to the bus and initialize the connection.
    def connect
      connect_to_tcp if @path.include? "tcp:" #connect to tcp socket
      connect_to_unix if @path.include? "unix:" #connect to unix socket
    end
    
    # Connect to a bus over tcp and initialize the connection.
    def connect_to_tcp
      #check if the path is sufficient
      if @path.include? "host=" and @path.include? "port="
        host,port,family = "","",""
        #get the parameters
        @path.split(",").each do |para|
          host = para.sub("tcp:","").sub("host=","") if para.include? "host="
          port = para.sub("port=","").to_i if para.include? "port="
          family = para.sub("family=","") if para.include? "family="
        end
        #dlog "host,port,family : #{host},#{port},#{family}"      
        begin
          #initialize the tcp socket
          @shared_socket = TCPSocket.new(host,port)
          #we'll use the flag later on
          @is_tcp = true
          init_connection
        rescue
          elog "Could not establish connection to: #{@path}, will now exit."
          exit(0) #a little harsh
        end
      else
        #Danger, Will Robinson: the specified "path" is not usable
        elog "supplied path: #{@path}, unusable! sorry."
      end
    end

    # Connect to an abstract unix bus and initialize the connection.
    def connect_to_unix
      @shared_socket = Socket.new(Socket::Constants::PF_UNIX,Socket::Constants::SOCK_STREAM, 0)
      parse_session_string
      if @transport == "unix" and @type == "abstract"
        if HOST_END == LIL_END
          sockaddr = "\1\0\0#{@unix_abstract}"
        else
          sockaddr = "\0\1\0#{@unix_abstract}"
        end
      elsif @transport == "unix" and @type == "path"
        sockaddr = Socket.pack_sockaddr_un(@unix)
      end
      socket.connect(sockaddr)
      init_connection
    end
    
    # Parse the session string (socket address).
    def parse_session_string
      path_parsed = /^([^:]*):([^;]*)$/.match(@path)
      @transport = path_parsed[1]
      adr = path_parsed[2]
      if @transport == "unix"
        adr.split(",").each do |eqstr|
          idx, val = eqstr.split("=")
          case idx
          when "path"
            @type = idx
            @unix = val
          when "abstract"
            @type = idx
            @unix_abstract = val
          when "guid"
            @guid = val
          end
        end
      end
    end

    # Send the buffer _buf_ to the bus using Connection#writel.
    def send(buf)
      socket.write(buf) unless socket.nil?
    end

    # Tell a bus to register itself on the glib main loop
    def glibize
      require 'glib2'
      # Circumvent a ruby-glib bug
      @channels ||= Array.new
      gio = GLib::IOChannel.new(socket.fileno)
      @channels << gio
      gio.add_watch(GLib::IOChannel::IN) do |c, ch|
        update_buffer
        messages.each do |msg|
          process(msg)
        end
        true
      end
    end

    # FIXME: describe the following names, flags and constants.
    # See DBus spec for definition
    NAME_FLAG_ALLOW_REPLACEMENT = 0x1
    NAME_FLAG_REPLACE_EXISTING = 0x2
    NAME_FLAG_DO_NOT_QUEUE = 0x4

    REQUEST_NAME_REPLY_PRIMARY_OWNER = 0x1
    REQUEST_NAME_REPLY_IN_QUEUE = 0x2
    REQUEST_NAME_REPLY_EXISTS = 0x3
    REQUEST_NAME_REPLY_ALREADY_OWNER = 0x4

    DBUSXMLINTRO = '<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.freedesktop.DBus.Introspectable">
    <method name="Introspect">
      <arg name="data" direction="out" type="s"/>
    </method>
  </interface>
  <interface name="org.freedesktop.DBus">
    <method name="RequestName">
      <arg direction="in" type="s"/>
      <arg direction="in" type="u"/>
      <arg direction="out" type="u"/>
    </method>
    <method name="ReleaseName">
      <arg direction="in" type="s"/>
      <arg direction="out" type="u"/>
    </method>
    <method name="StartServiceByName">
      <arg direction="in" type="s"/>
      <arg direction="in" type="u"/>
      <arg direction="out" type="u"/>
    </method>
    <method name="Hello">
      <arg direction="out" type="s"/>
    </method>
    <method name="NameHasOwner">
      <arg direction="in" type="s"/>
      <arg direction="out" type="b"/>
    </method>
    <method name="ListNames">
      <arg direction="out" type="as"/>
    </method>
    <method name="ListActivatableNames">
      <arg direction="out" type="as"/>
    </method>
    <method name="AddMatch">
      <arg direction="in" type="s"/>
    </method>
    <method name="RemoveMatch">
      <arg direction="in" type="s"/>
    </method>
    <method name="GetNameOwner">
      <arg direction="in" type="s"/>
      <arg direction="out" type="s"/>
    </method>
    <method name="ListQueuedOwners">
      <arg direction="in" type="s"/>
      <arg direction="out" type="as"/>
    </method>
    <method name="GetConnectionUnixUser">
      <arg direction="in" type="s"/>
      <arg direction="out" type="u"/>
    </method>
    <method name="GetConnectionUnixProcessID">
      <arg direction="in" type="s"/>
      <arg direction="out" type="u"/>
    </method>
    <method name="GetConnectionSELinuxSecurityContext">
      <arg direction="in" type="s"/>
      <arg direction="out" type="ay"/>
    </method>
    <method name="ReloadConfig">
    </method>
    <signal name="NameOwnerChanged">
      <arg type="s"/>
      <arg type="s"/>
      <arg type="s"/>
    </signal>
    <signal name="NameLost">
      <arg type="s"/>
    </signal>
    <signal name="NameAcquired">
      <arg type="s"/>
    </signal>
  </interface>
</node>
'

    def introspect_data(dest, path)
      m = DBus::Message.new(DBus::Message::METHOD_CALL)
      m.path = path
      m.interface = "org.freedesktop.DBus.Introspectable"
      m.destination = dest
      m.member = "Introspect"
      m.sender = unique_name
      if not block_given?
        # introspect in synchronous !
        send_sync(m) do |rmsg|
          if rmsg.is_a?(Error)
            raise rmsg
          else
            return rmsg.params[0]
          end
        end
      else
        send(m.marshall)
        on_return(m) do |rmsg|
          if rmsg.is_a?(Error)
            yield rmsg
          else
            yield rmsg.params[0]
          end
        end
      end
      nil
    end

    # Issues a call to the org.freedesktop.DBus.Introspectable.Introspect method
    # _dest_ is the service and _path_ the object path you want to introspect
    # If a code block is given, the introspect call in asynchronous. If not
    # data is returned
    #
    # FIXME: link to ProxyObject data definition
    # The returned object is a ProxyObject that has methods you can call to
    # issue somme METHOD_CALL messages, and to setup to receive METHOD_RETURN
    def introspect(dest, path)
      if not block_given?
        # introspect in synchronous !
        data = introspect_data(dest, path)
        pof = DBus::ProxyObjectFactory.new(data, self, dest, path)
        return pof.build
      else
        introspect_data(dest, path) do |data|
          yield(DBus::ProxyObjectFactory.new(data, self, dest, path).build)
        end
      end
    end

    # Exception raised when a service name is requested that is not available.
    class NameRequestError < Exception
    end

    # Attempt to request a service _name_.
    def request_service(name)
      r = proxy.RequestName(name, NAME_FLAG_REPLACE_EXISTING)
      raise NameRequestError if r[0] != REQUEST_NAME_REPLY_PRIMARY_OWNER
      @service = Service.new(name, self)
      return @service
    end

    # Set up a ProxyObject for the bus itself, since the bus is introspectable.
    # Returns the object.
    def proxy
      if @proxy == nil
        path = "/org/freedesktop/DBus"
        dest = "org.freedesktop.DBus"
        pof = DBus::ProxyObjectFactory.new(DBUSXMLINTRO, self, dest, path)
        @proxy = pof.build["org.freedesktop.DBus"]
      end
      @proxy
    end

    def update_buffer
      @update_mutex.synchronize { unsafe_update_buffer }
    end
    
    # Fill (append) the buffer from data that might be available on the
    # socket. 
    def unsafe_update_buffer
      return @buffer if socket.nil?
      unless @is_tcp
        begin
          @buffer += socket.read_nonblock(MSG_BUF_SIZE)
        rescue
          elog "something wrong with socket: #{@path}"
          wlog "will now exit, bye bye."
          exit(0)
        end
      else
        @buffer += socket.read_nonblock(MSG_BUF_SIZE)
        return @buffer
      end
    end

    # Get one message from the bus and remove it from the buffer.
    # Return the message.
    def pop_message
      ret = nil
      begin
        ret, size = Message.new.unmarshall_buffer(@buffer)
        @buffer.slice!(0, size)
      rescue IncompleteBufferException => e
        # fall through, let ret be null
      end
      ret
    end

    # Retrieve all the messages that are currently in the buffer.
    def messages
      ret = Array.new
      while msg = pop_message
        ret << msg
      end
      ret
    end

    # The buffer size for messages.
    MSG_BUF_SIZE = 4096

    # Update the buffer and retrieve all messages using Connection#messages.
    # Return the messages.
    def poll_messages
      ret = nil
      r, d, d = IO.select([socket], nil, nil, 0)
      if r and r.size > 0
        update_buffer
      end
      return messages
    end

    # Wait for a message to arrive. Return it once it is available.
    def wait_for_message
      if socket.nil?
        elog "Can't wait for messages, socket is nil."
        return
      end
      ret = pop_message
      while ret == nil
        r, d, d = IO.select([socket])
        if r and r[0] == socket
          update_buffer
          ret = pop_message
        end
      end
      return ret
    end

    # Send a message _m_ on to the bus. This is done synchronously, thus
    # the call will block until a reply message arrives.
    def send_sync(m, &retc) # :yields: reply/return message
      return if m.nil? #check if somethings wrong
      send(m.marshall)
      @method_call_msgs[m.serial] = m
      @method_call_replies[m.serial] = retc

      retm = wait_for_message
      
      return if retm.nil? #check if somethings wrong
      
      process(retm)
      until [DBus::Message::ERROR,DBus::Message::METHOD_RETURN].include?(retm.message_type) and retm.reply_serial == m.serial
        retm = wait_for_message
        process(retm)
      end
    end

    # Specify a code block that has to be executed when a reply for
    # message _m_ is received.
    def on_return(m, &retc)
      # Have a better exception here
      if m.message_type != Message::METHOD_CALL
        elog "Funky exception, occured."
        raise "on_return should only get method_calls"
      end
      @method_call_msgs[m.serial] = m
      @method_call_replies[m.serial] = retc
    end

    # Asks bus to send us messages matching mr, and execute slot when
    # received
    def add_match(mr, &slot)
      # check this is a signal.
      @signal_matchrules << [mr, slot]
      self.proxy.AddMatch(mr.to_s)
    end

    # Process a message _m_ based on its type.
    def process(m)
      return if m.nil? #check if somethings wrong
      case m.message_type
      when Message::ERROR, Message::METHOD_RETURN
        raise InvalidPacketException if m.reply_serial == nil
        mcs = @method_call_replies[m.reply_serial]
        if not mcs
          dlog "no return code for mcs: #{mcs.inspect} m: #{m.inspect}"
        else
          if m.message_type == Message::ERROR
            mcs.call(Error.new(m))
          else
            mcs.call(m)
          end
          @method_call_replies.delete(m.reply_serial)
          @method_call_msgs.delete(m.reply_serial)
        end
      when DBus::Message::METHOD_CALL
        if m.path == "/org/freedesktop/DBus"
          dlog "Got method call on /org/freedesktop/DBus"
        end
        # handle introspectable as an exception:
        if m.interface == "org.freedesktop.DBus.Introspectable" and
            m.member == "Introspect"
          reply = Message.new(Message::METHOD_RETURN).reply_to(m)
          reply.sender = @unique_name
          node = @service.get_node(m.path)
          raise NotImplementedError if not node
          reply.sender = @unique_name
          reply.add_param(Type::STRING, @service.get_node(m.path).to_xml)
          send(reply.marshall)
        else
          return if @service.nil?
          node = @service.get_node(m.path)
          return if node.nil?
          obj = node.object
          return if obj.nil?
          obj.dispatch(m) if obj
        end
      when DBus::Message::SIGNAL
        @signal_matchrules.each do |elem|
          mr, slot = elem
          if mr.match(m)
            slot.call(m)
            return
          end
        end
      else
        dlog "Unknown message type: #{m.message_type}"
      end
    end

    # Retrieves the service with the given _name_.
    def service(name)
      # The service might not exist at this time so we cannot really check
      # anything
      Service.new(name, self)
    end
    alias :[] :service

    # Emit a signal event for the given _service_, object _obj_, interface
    # _intf_ and signal _sig_ with arguments _args_.
    def emit(service, obj, intf, sig, *args)
      m = Message.new(DBus::Message::SIGNAL)
      m.path = obj.path
      m.interface = intf.name
      m.member = sig.name
      m.sender = service.name
      i = 0
      sig.params.each do |par|
        m.add_param(par[1], args[i])
        i += 1
      end
      send(m.marshall)
    end

    ###########################################################################
    private

    # Send a hello messages to the bus to let it know we are here.
    def send_hello
      m = Message.new(DBus::Message::METHOD_CALL)
      m.path = "/org/freedesktop/DBus"
      m.destination = "org.freedesktop.DBus"
      m.interface = "org.freedesktop.DBus"
      m.member = "Hello"
      send_sync(m) do |rmsg|
        @unique_name = rmsg.destination
        #dlog "Got hello reply. Our unique_name is #{@unique_name}, i feel special."
      end
    end

    # Initialize the connection to the bus.
    def init_connection
      @client = Client.new(socket)
      @client.authenticate
    end
  end # class Connection
end # module DBus
