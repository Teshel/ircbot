#!/usr/bin/ruby -w
#
# Ruby/IRC::Client
# v0.2.0 (Sciurus vulgaris)
# 31 May 2005
#
# Code & Design - J. Michaels <jmichaels@gmail.com
#

require 'socket'
require 'YAML'

module Enumerable
    def random
        self[rand( self.size )]
    end
end

module IRC
    module Client
        Version = 
    
        # isolate fugly regexs away from the cool kids
        Events = {
                    :join => /:([^ ]*)![~]*([^ ]*)@([^ ]*) JOIN :(#[^ \cm]*)\cm$/m,
                    :part => /:([^ ]*)![~]*([^ ]*)@([^ ]*) PART (#[^ ]+)(?: :)?([^\cm]*)\cm$/m,
                    :quit => /:([^ ]*)![~]*([^ ]*)@([^ ]*) QUIT :([^\cm]*\cm$)/m,
                    :nick => /:([^ ]*)![~]*([^ ]*)@([^ ]*) NICK :([^ \cm\n]+)/m,
                    :list => /:[^ ]+ 353 [^ ]+ = (#[^ ]+) :([^\cm\n]+)\cm$/m,
                    :kick => /:([^ ]*)![~]*([^ ]*)@([^ ]*) KICK (#[^ ]+) ([^ ]+) :([^\cm]*)\cm$/m,
                    :topic => /:([^ ]*)![~]*([^ ]*)@([^ ]*) TOPIC (#[^ ]+) :([^\cm]*)\cm$/m,
                    :privmsg => /:([^ ]*)![~]*([^ ]*)@([^ ]*) PRIVMSG (#[^ ]+) :([^\cm\001]*)\cm$/m,
                    :query => /:([^ ]*)![~]*([^ ]*)@([^ ]*) PRIVMSG ([^ #]+) :([^\cm]*)\cm$/m,
                    :action => /:([^ ]*)![~]*([^ ]*)@([^ ]*) PRIVMSG (#[^ ]+) :.*\001ACTION ([^\cm\001]*)\001\cm$/m
                 }
        
        class Interface
            attr_accessor :nick, :name, :info, :verbosity, :socket, :timeout
            
            def initialize( nick, user, info )
                @nick = nick
                @user = user
                @info = info
                @connected = false
                @reconnect = false
                @verbosity = 0
                @timeout = 0
            end
            
            def log( msg, v=1 )
                $stdout.puts( msg ) if @verbosity >= v
            end
            
            # dying is bad
            def keepalive
                loop do
                    if @timeout > 180
                        @timeout = 0
                        $stdout.puts "Lost connection, reconnecting."
                        @socket.close
                        @connected = false
                        @socket = TCPSocket.new( @host, @port )
                    end
                    sleep 1
                    @timeout += 1
                    log( "timeout: #{@timeout}", 4 ) if @timeout % 10 == 0
                end
            end
            
            def connect
                @socket = TCPSocket.new( @host, @port )
                @keepalive_thread = Thread.new { self.keepalive }
                
                loop do
                    catch (:reconnect) do
                        begin
                            loop do 
                                line = @socket.gets
                                log line
                                @timeout = 0
                                throw :reconnect if @reconnect
                
                                unless @connected
                                    log "sending NICK"
                                    @socket.puts "NICK #{@nick}"
                                    log "NICK sent, sending USER"
                                    @socket.puts "USER #{@user} #{Socket.gethostname} #{@host} :#{@info}"
                                    @connected = true
                                    #Thread.new { self.handle_connected }
                                end
                                if line =~ /^:[^ ]* 433 / # Refuse nick
                                    if @nick =~ /^([^ ]+)_\d+$/
                                        @nick = $1 + "_" + rand( 10000 ).to_s
                                    else
                                        @nick += "_" + rand( 10000 ).to_s
                                    end
                                    log "resending NICK"
                                    @socket.puts "NICK #{@nick}"
                                end
                                if ( line =~ /^:([^ ]+) 001 #{@nick}/ )
                                    log "Joining channels:"
                                    @channels.each do |channel|
                                        log "  #{channel}"
                                        @socket.puts "JOIN #{channel}"
                                    end
                                end
                                
                                if @connected
                                    # Make sure we stay connected. Important.
                                    @socket.puts "PING #{$~[1]}" if ( line =~ /^PING (.*)/ )
                                    
                                    # if self.dispatch is implemented, match for each IRC event
                                    if self.respond_to? :dispatch
                                        Events.each do |key, value|
                                            match = value.match( line )
                                            
                                            if match
                                                results = Hash.new
                                                results[:event] = ("on_" + key.to_s).to_sym
                                                
                                                # build the results hash
                                                if key == :join
                                                    if match[1] == @nick
                                                        event = :on_self_join
                                                    else
                                                        results[:nick] = match[1]
                                                    end
                                                end
                                                if key == :privmsg
                                                    if match[5] =~ /^\s*#{@nick}\s*[;:,]?\s*(.+?)\s*$/i
                                                        results[:command] = $1.dup
                                                    end
                                                end
                                                if [:part, :quit, :privmsg, :action, :topic, :nick, :query, :kick].include? key
                                                    results[:nick] = match[1]
                                                    results[:user] = match[2]
                                                    results[:host] = match[3]
                                                end
                                                if [:join, :part, :topic, :query, :privmsg, :action, :kick].include? key
                                                    results[:channel] = match[4]
                                                end
                                                if key == :list
                                                    results[:channel] = match[1]
                                                    results[:nicks] = match[2]
                                                end
                                                if [:part, :kick, :query, :action, :privmsg].include? key
                                                    results[:message] = match[5]
                                                end
                                                if key == :topic
                                                    results[:topic] = match[5]
                                                end
                                                if key == :nick
                                                    results[:new_nick] = match[4]
                                                end
                                                
                                                # send results to dispatch
                                                self.dispatch( results )
                                            end
                                        end
                                    end
                                end
                            end
                        rescue IOError => e
                            log e.message, 3
                            throw :reconnect
                        end
                    end
                    puts "Restarting connect loop"
                    @reconnect = false
                    sleep 5
                end
            end
            
            def nick=( newNick )
                # Set for this object.
                @nick = newNick
                
                # Set remotely.
                @socket.puts( "NICK #{@nick}" )
            end
        end
        
        class Client < Interface
            attr_accessor :responders, :instance_data
            
            def initialize( config_file='config.yaml' )
                self.load_config( config_file )
                
                super @config[:nick], @config[:user], @config[:info]
                
                self.load_instance_data
                @channels = @config[:channels] || []
                @host = @config[:host]
                @port = @config[:port] || 6667
                @responders = []
                #self.add_responder( Users )
                self.add_responder( Log )
                (@config[:responders]||"").split(/[ ,]/).compact.map{|resp| eval resp}.each{|resp| self.add_responder( resp ) if resp }
                
                Thread.new do
                    loop do
                        sleep @config[:save_interval] || 120
                        self.save_instance_data
                    end
                end
            end
            
            # dispatch informs all attached responders of events 
            def dispatch( results )
                # attach a timestamp
                results[:timestamp] = Time.now
                @responders.each do |responder|
                    begin
                        responder.new( self, results ).send( :on_anything ) if responder.instance_methods.include? "on_anything"
                        responder.new( self, results ).send( results[:event] ) if responder.instance_methods.include? results[:event].to_s
                    rescue Exception => e
                        log e.message, 0
                        log e.backtrace.join( "\n" ), 0
                    end
                end
            end
            
            def add_responder responder
                @responders << responder
                @instance_data[responder.to_s] ||= Hash.new
                responder.data = @instance_data[responder.to_s]
                #responder.new( self, Hash.new ).init
            end
            
            def remove_responder r
                @responders.delete r
            end
            
            def save_instance_data file="#{@nick}_instance_data.yaml"
                #@instance_data[:resp] = Hash.new
                #@responders.each do |resp|
                #    @instance_data[:resp][resp.class.to_s] = resp.data
                #end
                log( "Saving instance data to #{file}.", 2 )
                File.open file, "w" do |f| YAML.dump @instance_data, f end
            end
            
            def load_instance_data file="#{@nick}_instance_data.yaml"
                log "Loading instance data from #{file}.", 2
                ld = YAML.load File.open( file, "r" ) if File.exist? file
                #fail "Corrupted instance data file. Delete or fix it and try again." unless (ld.is_a? Hash) 
                @instance_data = ld || Hash.new
                
                # hint: k is a class.
                #(ld[:resp]||{}).each { |k,v| eval(k).data = v }
            end
            
            def load_config file
                # custom config parser, very simplistic
                @config = Hash.new
                File.open file, "r" do |f| f.readlines.each do |line|
                    @config[$1.to_sym] = $2.dup if line =~ /^\s*(\w+)\s*:\s*(.+?)\s*$/
                end end
                
                # check the config to make sure it's valid
                error = Array.new
                error.push "" unless @config[:info]
                
                #fail 
            end
            
            def say message, target
                log "sending message to #{target}", 0
                @socket.puts "PRIVMSG #{target} :#{message}"
            end
            
            def notice message, target
                @socket.puts "NOTICE #{target} :#{message}"
            end
            
            def emote action, target
                log "sending emote"
                @socket.puts "PRIVMSG #{target} :\001ACTION #{action}\001"
            end
            
            def join channel
                @socket.puts "JOIN #{channel}"
                #@chanlist += " #{channel}"
            end
            
            def part channel
                @socket.puts "PART #{channel}"
                @chanlist = @chanlist.find_all { |chan| chan != channel }
            end
            
            def quit message=""
                @socket.puts "QUIT #{message}"
            end
        end
        
        def self.new_with_responders resp, config_file='config.yaml'
            ret = Client.new( config_file )
            ret.add_responder( resp )
            ret
        end
        
        def self.new
            Client.new
        end
        
        class Responder
            attr_accessor :channel, :nick, :message, :user, :host, :topic, :nicks, :command, :new_nick, :timestamp, :event
        
            def initialize client, results
                @client, @results = client, results
                
                results.each do |key, value|
                    self.send "#{key}=", value
                end
            end
            
            def self.data
                @@data
            end
            
            def self.data= v
                @@data = v
            end
            
            def on_init
            
            end
            
            def init
                @@data ||= Hash.new
            end
            
            def require_responder resp
                @client.add_responder resp unless @client.responders.include? resp
            end
            
            def say message, channel=@channel
                @client.say message, channel
            end
            
            def emote message, channel=@channel
                @client.emote message, channel
            end
            
            def this_user
                @client.instance_data[:users][@nick]
            end
            
            def self.method_missing sym, *args, &block
                if sym.to_s =~ /^on_\w+$/
                    if block
                        define_method sym, &block
                    else
                        define_method sym  do
                            args.flatten.each do |arg| self.send arg end
                            return nil
                        end
                    end
                else super sym, args, &block
                end
            end
        end
        
        class Users < Responder
            def on_init
                @@data ||= Hash.new
            end
            
            def on_anything
                @@data[nick] ||= Hash.new if nick
            end
            
            def on_join
                @@data[nick][:channels] ||= Array.new
                @@data[nick][:channels].push channel
            end
            
            def on_part
                @@data[nick][:channels].pop channel if users[nick][:channels]
            end
            
            def on_quit
                @@data[nick][:channels] = nil
            end
            
            def on_nick
                @@data[new_nick] ||= Hash.new
                @@data[new_nick][:channels] = users[nick][:channels].dup
                @@data[nick][:channels] = nil
            end
        end
        
        
        class Log < Responder
            def on_init
                @@data ||= Hash.new
            end
            
            def on_anything
                @@data[channel||:general] ||= Array.new
                @@data[channel||:general].push @results.dup
            end
            
            on_privmsg do
                if message =~ /^randline/
                    say @client.instance_data.keys.join(" ")
                    say @client.instance_data.values.map{|v| v[:channel]}.join(" ")
                    say self.class.to_s
                    say @client.instance_data[self.class.to_s]
                end
            end
        end
        
        class Dynamic < Responder
            def on_privmsg
                begin
                    if message =~ /^rehash (\w+)$/i
                        load "./#{$1}.rb"
                    end
                rescue LoadError
                    say "Error loading #{$1}.rb"
                end
            end
        end
    end
end