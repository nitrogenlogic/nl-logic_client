#!/usr/bin/env ruby
# Displays information about the running graph.
# (C)2011 Mike Bourgeous

require 'bundler/setup'
require 'nl/logic_client'

$succeeded = false

class ShowInfoClient < NL::LC::Client
  def post_init
    super
    get_info do |info|
      info.each do |k, v|
        puts "#{k}=#{v}"
      end
      do_command 'bye'
      close_connection_after_writing
    end
  end

  def connection_completed
    super
    $succeeded = true
  end

  def unbind
    super
    puts "An error occurred while getting the graph info." unless $succeeded
    EM::stop_event_loop
  end
end

def show_info hostname=nil
  hostname ||= 'localhost'
  EM.connect(hostname, 14309, ShowInfoClient)
end

if __FILE__ == $0
  EM::run {
    EM.error_handler { |e|
      puts "Error: "
      p e
    }
    show_info ARGV[0]
  }

  exit $succeeded ? 0 : 7
end
