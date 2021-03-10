# Ruby client interface for the logic system protocol, powered by EventMachine.
# (C)2012-2016 Mike Bourgeous

require 'eventmachine'
require_relative 'logic_client/version'

module NL
  module LogicClient
    LS_PORT = 14309

    module KeyValueParser
      KVREGEX = %r{(\A|^|\s)("(\\.|[^"])*"|[^" \t\r\n=][^ \t\r\n=]*)=("(\\.|[^"])*("|$)|[^ \t\r\n]+)}

      # Replacement on the left, original on the right
      UNESCAPES = {
        't' => "\t",
        'n' => "\n",
        'r' => "\r",
        'v' => "\v",
        'f' => "\f",
        'a' => "\a",
        '"' => '"'
      }

      # Original on the left, replacement on the right
      ESCAPES = UNESCAPES.invert

      # TODO: Replace this key-value parser with the C-based one from knc.  See
      # nl-knd_client.

      # Removes surrounding quotes from and parses C-style escapes within the
      # given string.  Does not handle internal quoting the way a shell would.
      # Returns an unescaped copy, leaving the original string unmodified.
      def self.unescape(str, dequote=true, esc="\\")
        if str.length == 0
          return str
        end

        newstr = ''
        i = 0
        quoted = false
        if dequote && str[0] == '"'
          quoted = true
          i += 1
        end

        until i == str.length
          if str[i] == esc
            # Remove a lone escape at the end of the string
            break if i == str.length - 1

            i += 1
            c = str[i]
            case c
            when 'x'
              puts "Hexadecimal escape", c.inspect
              # Hexadecimal escape TODO: Get up to two hex digits
              # TODO: Safe \u unicode escape
            when esc
              # Escape character
              newstr << esc
            else
              # Standard escape
              if UNESCAPES.has_key? c
                # Matching character -- process escape sequence
                newstr << UNESCAPES[c]
              else
                # No matching character -- pass escape sequence unmodified
                newstr << esc
                newstr << c
              end
            end
          else
            # Ordinary character
            unless i == str.length - 1 && quoted && str[i] == '"'
              newstr << str[i]
            end
          end
          i += 1
        end

        newstr
      end

      # Parses a multi-element quoted key-value pair string into a hash.  Keys
      # and values should be quoted independently (e.g. "a"="b" not "a=b").
      def self.kvp(str)
        pairs = {}
        str.scan(KVREGEX) do |match|
          if match[1] != nil && match[3] != nil
            pairs[unescape(match[1])] = unescape(match[3])
          end
        end
        pairs
      end
    end

    KVP = KeyValueParser

    # Represents a deferred logic system command.  Use the callback and errback
    # methods from EM::Deferrable to add callbacks to be executed on command
    # success/failure.
    class Command
      include EM::Deferrable

      attr_reader :lines, :data, :data_size, :message, :name, :argstring

      def initialize(name, *args)
        @name = name
        @args = args
        @argstring = (args.length > 0 && " #{@args.map {|s| s.to_s.gsub(',', '') if s != nil }.join(',')}") || ''
        @linecount = 0
        @lines = []
        @data_size = 0
        @data = nil
        @message = ""

        timeout(5)
      end

      # Returns true if successful, false if failed, nil if the
      # command isn't finished.
      def success?
        case @deferred_status
        when :succeeded
          true
        when :failed
          false
        else
          nil
        end
      end

      # Returns true if this command is waiting for data.
      def want_data?
        @data_size > 0
      end

      # Called by Client when an OK line is received
      def ok_line(message)
        @message = message

        # TODO: Change to a protocol more like the one I designed for HATS
        # Server, with different response types for text/data/status.
        case @name
        when 'stats', 'subs', 'lst', 'lstk', 'help'
          @linecount = message.to_i
        when 'download'
          @data_size = message.gsub(/[^0-9]*(\d+).*/, '\1').to_i
        end

        if @linecount == 0 && @data_size == 0
          succeed self
          return true
        end

        return false
      end

      # Called by Client when an ERR line is received
      def err_line(message)
        @message = message
        fail self
      end

      # Called by Client to add a line
      # Returns true when enough lines have been received
      def add_line(line)
        @lines << line
        @linecount -= 1
        if @linecount == 0
          succeed self
        end
        return @linecount <= 0
      end

      # Called by client to add binary data
      def add_data(data)
        @data = @data || ''.force_encoding('BINARY')
        @data << data
        @data_size -= data.bytesize
        if @data_size == 0
          succeed self
        elsif @data_size < 0
          raise "Too many bytes given to data-receiving Command."
        end
        return @data_size <= 0
      end

      # Returns the command line sent to the logic system for this command
      def to_s
        "#{@name}#{@argstring}"
      end

      # Returns a description of the command's contents, useful for debugging
      def inspect
        %Q{#<Command: cmd=#{@name} n_lines=#{@lines.length} n_data=#{@data && @data.length}>}
      end
    end

    # Internally represents a subscription to a value on the logic system
    class Subscription
      attr_reader :value
      attr_reader :id

      # Initializes a subscription.  The block will be called with
      # object ID, parameter ID, and parameter value.
      # TODO: Use line as parameter instead?
      def initialize(obj, id, &block)
        if obj == nil || id == nil || block == nil
          raise "Nil parameter to Subscription constructor"
        end

        unless obj.respond_to?(:to_i) and id.respond_to?(:to_i)
          raise "Object and ID must be integers"
        end

        @value = nil
        @obj = obj.to_i
        @id = id.to_i
        @cb = block
      end

      # Calls the callback when the value is changed.  The call to
      # the callback is deferred using the event reactor.
      def value=(val)
        @value = val
        EM.next_tick {
          cb.call @obj, @id, @value
        }
        # TODO: Support multiple callbacks per parameter using
        # a reference count to unsubscribe
      end

      # Parses the key-value pair line from a subscription message
      def parse(kvpline)
        # TODO: Parse the message (move kvp tools from KNC
        # client.rb into a private utility gem?)
      end
    end

    # Converts a string value to the given logic system type name (int,
    # float, string, data).
    def self.string_to_type(str, type)
      case type
      when 'int'
        return str.to_i
      when 'float'
        return str.to_f
      when 'string'
        return KVP.unescape(str)
      when 'data'
        raise "Data type not yet supported."
      else
        raise "Unsupported data type: #{type}."
      end
    end

    # Represents an exported parameter to be returned by get_exports
    class Export
      attr_reader :objid, :obj_name, :param_name, :index, :type, :value
      attr_reader :min, :max, :def, :hide_in_ui, :read_only

      # Parses an export key-value line received from the logic system server
      def initialize(line)
        kvmap = KVP.kvp line

        @objid = kvmap['objid'].to_i
        @index = kvmap['index'].to_i
        @type = kvmap['type']
        @value = LC.string_to_type(kvmap['value'], @type)
        @min = LC.string_to_type(kvmap['min'], @type)
        @max = LC.string_to_type(kvmap['max'], @type)
        @def = LC.string_to_type(kvmap['def'], @type)
        @obj_name = kvmap['obj_name']
        @param_name = kvmap['param_name']
        @hide_in_ui = kvmap['hide_in_ui'] == 'true'
        @read_only = kvmap['read_only'] == 'true'
      end

      # Formats this export's info as it would come from the logic system server
      def to_s
        # TODO: Quote strings/escape them the same way as the logic system
        "#{@objid},#{@index},#{@type},#{@value.inspect} (#{@obj_name}: #{@param_name})"
      end

      # Formats this export's info as key-value pairs
      def to_kvp
        %Q{objid=#{@objid} index=#{@index} type=#{@type.inspect} read_only=#{@read_only} } <<
        %Q{hide_in_ui=#{@hide_in_ui} min=#{@min.inspect} max=#{@max.inspect} def=#{@def.inspect} } <<
        %Q{obj_name=#{@obj_name.inspect} param_name=#{@param_name.inspect} value=#{@value.inspect}}
      end

      # Stores this export's info in a hash
      def to_h
        { :objid => @objid, :obj_name => @obj_name, :param_name => @param_name,
          :min => @min, :max => @max, :def => @def, :hide_in_ui => @hide_in_ui,
          :read_only => @read_only, :index => @index, :type => @type, :value => @value
        }
      end
    end

    # Manages a connection to a logic system
    class Client < EM::Connection
      include EM::P::LineText2

      attr_reader :verstr, :version

      # Conmap parameter is the hash entry in LC::@@connections
      def initialize(conmap=nil)
        super
        @binary = :none
        @commands = []
        @active_command = nil
        @subscriptions = {}
        @con = conmap
        @verstr = ''
        @version = nil
      end

      # Override this method to implement a connection-completed callback (be
      # sure to call super)
      def connection_completed
        cmd = get_version do |msg|
          @verstr = msg
          @version = msg[/[0-9]+\.[0-9]+\.[0-9]+/]
        end
        cmd.errback do |cmd|
          close_connection
        end

        @con_success = true
        if @con
          @con[:connected] = true
          @con[:callbacks].each do |cb|
            cb.call(self) if cb && cb.respond_to?(:call)
          end
          @con[:callbacks].clear
          @con[:errbacks].clear
        end
        super
      end

      def unbind
        # TODO: Call the error handlers for any pending commands
        # TODO: Add the ability to register unbind handlers

        unless @con_success
          if @con
            @con[:errbacks].each do |eb|
              eb.call() if eb && eb.respond_to?(:call)
            end
          end
        end

        if @con
          LC.connections.delete(@con[:hostname])
        end
      end

      def receive_line(data)
        # Feed lines into any command waiting for data
        if @active_command
          @active_command = nil if @active_command.add_line data
          return
        end

        # No active command, so this must be the beginning of a response (e.g. OK, ERR, SUB)
        type, message = data.split(" - ", 2)

        case type
        when "OK"
          if @commands.length == 0
            puts '=== ERROR - Received OK when no command was waiting ==='
          else
            cmd = @commands.shift
            unless cmd.ok_line message
              @active_command = cmd
              set_binary_mode(cmd.data_size) if cmd.want_data?
            end
          end
        when "ERR"
          if @commands.length == 0
            puts '=== ERROR - Received ERR when no command was waiting ==='
          end
          @commands.shift.err_line message
        when "SUB"
          # TODO: Check for a callback in the subscription table
          puts "TODO: Implement subscription handling"
        else
          puts "=== ERROR - Unknown response '#{data}' ==="
          # TODO: Clear pending commands or disconnect at this point?
        end
      end

      def receive_binary_data(data)
        if @active_command
          raise "Received data for a command not expecting it!" unless @active_command.want_data?
          @active_command = nil if @active_command.add_data data
        end
      end

      # Defers execution of a command.  The block, if specified, will be called
      # with a Command object upon successful completion of the command.  For
      # more control over a command's lifecycle, including specifying an error
      # callback, see the Command class.  Returns the Command object used for
      # this command.  TODO: Add a timeout that calls any error handlers if the
      # command doesn't return quickly.
      def do_command(command, *args, &block)
        if command.is_a? Command
          cmd = command
        else
          cmd = Command.new command, *args
        end

        if block != nil
          cmd.callback { |*args|
            block.call *args
          }
        end

        send_data "#{cmd.to_s}\n"
        @commands << cmd

        return cmd
      end

      # Calls the given block with the message received from the ver command.
      # Returns the Command used to process the request.
      def get_version(&block)
        return do_command('ver') { |cmd|
          block.call cmd.message
        }
      end

      # Calls the given block with the current list of subscriptions (an array
      # of lines received from the server).  Returns the Command used to
      # process the request.
      def get_subscriptions(&block)
        return do_command("subs") { |cmd|
          block.call cmd.lines
        }
      end

      # Calls the given block with the list of exported parameters (an array of
      # lines received from the server).  Returns the Command used to process
      # the request.
      def get_exports(&block)
        return do_command("lstk") { |cmd|
          block.call cmd.lines.map { |line| Export.new line }
        }
      end

      # Calls the given block with a hash containing information about the
      # currently-running logic graph.  Returns the Command used to process the
      # request.
      def get_info(&block)
        return do_command("inf") { |cmd|
          info = KVP.kvp cmd.message
          begin
            info['id'] = info['id'].to_i
            info['numobjs'] = info['numobjs'].to_i
            info['period'] = info['period'].to_i
            info['avg'] = info['avg'].to_i
            info['revision'] = info['revision'].split('.', 2).map { |v| v.to_i }
          rescue
          end
          block.call info
        }
      end

      # Calls the given block with the requested value.  Returns the Command
      # used to process the request.
      def get(objid, param_index, &block)
        return do_command("get", objid, param_index) { |cmd|
          type, value = cmd.message.split(' - ', 2)
          block.call LC.string_to_type(value, type)
        }
      end

      # Calls the given block with a Command object after successfully setting
      # the given value.  Returns the Command used to process the request.
      def set(objid, param_index, value, &block)
        return do_command("set", objid, param_index, value) { |cmd|
          block.call cmd if block
        }
      end

      # Sets multiple parameters and calls the given block with the number of
      # sucessful sets, and a copy of the multi array with results added to the
      # individual hashes.  Multi should be an array of hashes, with each hash
      # containing :objid, :index, and :value.  A success/error result for each
      # value will be stored in :result, and the associated Command object
      # stored in :command.  Returns the first Command object in the sequence
      # (not particularly useful), or nil if multi is empty.
      def set_multi(multi, &block)
        raise ArgumentError, "Pass an array of hashes to set_multi" unless multi.is_a? Array

        if multi.length == 0
          block.call(0, multi) if block
          return nil
        end

        iter = multi.each
        count = 0

        cb = proc { |cmd|
          begin
            v = iter.next
            v[:command] = cmd
            v[:result] = cmd.success?
            count += 1 if cmd.success?

            v = iter.peek
            nc = set(v[:objid], v[:index], v[:value])
            nc.callback { |*a| cb.call *a }
            nc.errback { |*a| cb.call *a }
          rescue ::StopIteration
            block.call count, multi
          end
        }

        v = iter.peek
        nc = set(v[:objid], v[:index], v[:value])
        nc.callback { |*a| cb.call *a }
        nc.errback { |*a| cb.call *a }

        return nc
      end

      # TODO: Methods for more commands
    end

    # Key=hostname, value=hash containing:
    # 	{ :connected => bool,
    # 	:client => Client,
    # 	:callbacks => [],
    # 	:errbacks => []
    # 	}
    @@connections = {}
    def self.connections
      @@connections
    end

    # If a connection to the given exact hostname exists, then the given
    # block will be called with the corresponding LC::Client object as its
    # parameter.  Otherwise a connection request to the given host name is
    # queued, and block and errback will be added to the list of success
    # and error callbacks that will be called when the connection is made
    # or fails.  Success callbacks are called with the Client object as
    # their first parameter.  Error callbacks are called with no
    # parameters.
    def self.get_connection(hostname, errback=nil, &block)
      raise "You must pass a success block to get_connection." if block == nil
      raise "EventMachine reactor must be running." unless EM.reactor_running?

      con = @@connections[hostname]
      unless con
        con = {
          :hostname => hostname,
          :connected => false,
          :callbacks => [],
          :errbacks => []
        }
        con[:client] = EM.connect(hostname, LS_PORT, Client, con)
        @@connections[hostname] = con
      end

      if con[:connected]
        block.call con[:client]
      else
        con[:callbacks] << block if block
        con[:errbacks] << errback if errback
      end
    end

    # If a connection to the given exact hostname exists, then the
    # connection's Client object will be returned.  Otherwise, nil will be
    # returned.
    def self.get_client(hostname)
      @@connections[hostname] && @@connections[hostname][:client]
    end
  end

  LC = LogicClient
end
