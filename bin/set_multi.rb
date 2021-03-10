#!/usr/bin/env ruby

require 'bundler/setup'
require 'nl/logic_client'

EM.run {
  NL::LC.get_connection(
    ARGV[0] || 'localhost',
    proc { puts 'Error connecting to server'; EM.stop_event_loop }
  ) do |c|
    p c
    c.set_multi [{:objid => 0, :index => 0, :value => '0x55'}] do |count, list|
      p "#{count} of #{list.length}"
      p list
      EM.stop_event_loop
    end
  end
}
