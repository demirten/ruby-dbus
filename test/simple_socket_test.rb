#!/usr/bin/ruby

require 'rubygems'
require 'rofl'
require 'dbus'

=begin
puts "NOW LISTING SYSTEM BUS:\n"

#show services on system bus
sysbus = DBus::SystemBus.instance
puts "\tsystem bus - listnames:"
sysbus.proxy.ListNames[0].each { |name| puts "\t\tservice: #{name}" } unless sysbus.nil?
=end
#test sockets

puts "NOW LISTING SESSION BUS:\n"

#show services on a tcp session bus
#socket_name = "unix:path=/tmp/socket_test_session_bus_socket" #look at: config/remote.session.dbus.conf
#socket_name = "tcp:host=0.0.0.0,port=2687,family=ipv4" #look at: config/remote.session.dbus.conf
socket_name = "tcp:host=10.11.12.13,port=2687,family=ipv4" #look at: config/remote.session.dbus.conf
dlog "\tsession socket name: #{socket_name}"
DBus.const_set("SessionSocketName", socket_name) #overwrite the modules constant
sesbus = DBus::SessionBus.instance
dlog "\tsession bus - listnames:"
sesbus.proxy.ListNames[0].each { |name| dlog "\t\tservice: #{name}" } unless sesbus.nil?
