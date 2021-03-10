#!/usr/bin/env ruby
# Prints a list of exported parameters on the specified logic controller.
# (C)2011 Mike Bourgeous

require 'bundler/setup'
require 'nl/logic_client'

$list_exports_succeeded = false

def list_exports hostname=nil
  hostname ||= 'localhost'

  errback = proc {
    puts "Connection to the server failed."
    EM::stop_event_loop
  }
  NL::LC.get_connection(hostname, errback) do |c|
    cmd = c.get_exports do |exports|
      $list_exports_succeeded = true
      if ARGV[1] == "--kvp"
        puts *(exports.map { |e| e.to_kvp })
      else
        puts *exports
      end
      cmd2 = c.do_command 'bye' do
        EM::stop_event_loop
      end
      cmd2.errback do
        EM::stop_event_loop
      end
    end
    cmd.errback do
      EM::stop_event_loop
    end
  end
end

if __FILE__ == $0
  EM::run {
    list_exports ARGV[0]
  }

  exit $list_exports_succeeded ? 0 : 7
end

