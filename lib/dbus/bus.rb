# dbus.rb - Module containing the low-level D-Bus implementation
#
# This file is part of the ruby-dbus project
# Copyright (C) 2007 Arnaud Cornet and Paul van Tilburg
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License, version 2.1 as published by the Free Software Foundation.
# See the file "COPYING" for the exact licensing terms.
require 'singleton'

# = D-Bus main module
#
# Module containing all the D-Bus modules and classes.
module DBus
  # This represents a remote service. It should not be instancied directly
  # Use Bus::service()
  class Service
    # The service name.
    attr_reader :name
    # The bus the service is running on.
    attr_reader :bus
    # The service root (FIXME).
    attr_reader :root

    # Create a new service with a given _name_ on a given _bus_.
    def initialize(name, bus)
      @name, @bus = name, bus
      @root = Node.new("/")
    end

    # Determine whether the serice name already exists.
    def exists?
      bus.proxy.ListName.member?(@name)
    end

    # Perform an introspection on all the objects on the service
    # (starting recursively from the root).
    def introspect
      if block_given?
        raise NotImplementedError
      else
        rec_introspect(@root, "/")
      end
      self
    end

    # Retrieves an object at the given _path_.
    def object(path)
      node = get_node(path, true)
      if node.object.nil?
        node.object = ProxyObject.new(@bus, @name, path)
      end
      node.object
    end

    # Export an object _obj_ (an DBus::Object subclass instance).
    def export(obj)
      obj.service = self
      get_node(obj.path, true).object = obj
    end

    # Get the object node corresponding to the given _path_. if _create_ is
    # true, the the nodes in the path are created if they do not already exist.
    def get_node(path, create = false)
      n = @root
      path.sub(/^\//, "").split("/").each do |elem|
        if not n[elem]
          if not create
            return nil
          else
            n[elem] = Node.new(elem)
          end
        end
        n = n[elem]
      end
      if n.nil?
        wlog "Unknown object #{path.inspect}"
      end
      n
    end

    #########
    private
    #########

    # Perform a recursive retrospection on the given current _node_
    # on the given _path_.
    def rec_introspect(node, path)
      xml = bus.introspect_data(@name, path)
      intfs, subnodes = IntrospectXMLParser.new(xml).parse
      subnodes.each do |nodename|
        subnode = node[nodename] = Node.new(nodename)
        if path == "/"
          subpath = "/" + nodename
        else
          subpath = path + "/" + nodename
        end
        rec_introspect(subnode, subpath)
      end
      if intfs.size > 0
        node.object = ProxyObjectFactory.new(xml, @bus, @name, path).build
      end
    end
  end

  # = Object path node class
  #
  # Class representing a node on an object path.
  class Node < Hash
    # The D-Bus object contained by the node.
    attr_accessor :object
    # The name of the node.
    attr_reader :name

    # Create a new node with a given _name_.
    def initialize(name)
      @name = name
      @object = nil
    end

    # Return an XML string representation of the node.
    def to_xml
      xml = '<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
      <node>'

      self.each_pair do |k, v|
        xml += "<node name=\"#{k}\" />"
      end
      if @object
        @object.intfs.each_pair do |k, v|
          xml += %{<interface name="#{v.name}">\n}
          v.methods.each_value { |m| xml += m.to_xml }
          v.signals.each_value { |m| xml += m.to_xml }
          xml +="</interface>\n"
        end
      end
      xml += '</node>'
      return xml
    end

    # Return inspect information of the node.
    def inspect
      # Need something here
      "<DBus::Node #{sub_inspect}>"
    end

    # Return instance inspect information, used by Node#inspect.
    def sub_inspect
      s = ""
      if not @object.nil?
        s += "%x " % @object.object_id
      end
      s + "{" + keys.collect { |k| "#{k} => #{self[k].sub_inspect}" }.join(",") + "}"
    end
  end # class Inspect

  # = D-Bus session bus class
  #
  # The session bus is a session specific bus (mostly for desktop use).
  # This is a singleton class.
  class SessionBus < Connection
    include Singleton
    
    # Get the the default session bus.
    def initialize socket_name=SessionSocketName
      super(socket_name)
      connect
      send_hello
    end
  end

  # = D-Bus system bus class
  #
  # The system bus is a system-wide bus mostly used for global or
  # system usages.  This is a singleton class.
  class SystemBus < Connection
    include Singleton

    # Get the default system bus.
    def initialize socket_name=SystemSocketName
      super(socket_name)
      connect
      send_hello
    end
  end

  # FIXME: we should get rid of these singeltons

  def DBus.system_bus
    SystemBus.instance
  end

  def DBus.session_bus
    SessionBus.instance
  end

  # = Main event loop class.
  #
  # Class that takes care of handling message and signal events
  # asynchronously.  *Note:* This is a native implement and therefore does
  # not integrate with a graphical widget set main loop.
  class Main
    # Create a new main event loop.
    def initialize
      @buses = Hash.new
    end

    # Add a _bus_ to the list of buses to watch for events.
    def <<(bus)
      @buses[bus.socket] = bus
    end

    # Run the main loop. This is a blocking call!
    def run
      loop do
        ready, dum, dum = IO.select(@buses.keys)
        ready.each do |socket|
          b = @buses[socket]
          begin
            b.update_buffer
          rescue EOFError
            return # the bus died
          end
          while m = b.pop_message
            b.process(m)
          end
        end
      end
    end
  end # class Main
end # module DBus
