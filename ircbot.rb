#!/usr/local/bin/ruby -w
# ircbot.rb
# v0.1.1 (Euler)
#
# Code & Design: J. Michaels <jmichaels@gmail.com>
#

require './ircclient.rb'

module Enumerable
    def random
        self[rand( self.size )]
    end
end

class Handler
    def initialize( results, client )
        @results = results
        @client = client
    end
    
    def say( message, channel=@results[:channel] )
        @client.say( message )
    end
    
    def emote( message, channel=@results[:channel] )
        @client.emote( message, channel )
    end
    
    def respond( block )
        channel = @results[:channel]
        message = @results[:message]
        hostmask = @results[:hostmask]
        nick = @results[:nick]
        bot_nick = @client.nick
        eval block
    end
end

class Responder
    attr_accessor :triggers

    def initialize( nick, name, info )
        super( nick, name, info )
        
        @triggers = Hash.new
    end
    
    def handle_otherJoin( results )
        channel = results[:channel]

        if @triggers[:join]
            puts "handling otherJoin, sending to triggers"
            @triggers[:join].each do |trig|
                $here = binding
                eval(trig)
            end
        end
        
        puts "there are no triggers" unless @triggers[:join]
    end
    
    def handle_privmsg( results )
        
    end
    
    def on_trig( trigger, &trig )
        #@triggers = Hash.new unless @triggers
        @triggers[trigger] = Array.new unless @triggers[trigger]
        @triggers[trigger] << trig
    end
    
    def on_join( trigger )
        @triggers[:join] = Array.new unless @triggers[:join]
        @triggers[:join] << trigger
    end
    
    def loadmod( *modus )
        modus.each |modu|
            if modu::IRCHandlers
                if modu::IRCHandlers[:join]
                    modu::IRCHandlers[:join].each { |handlers| on_join( modu ) }
                end
            end
        end
    end
end

module SpamBot
    Greeter = %{
        say "Hi!", channel
    }
    
    IRCHandlers = {:join => [Greeter]}
end

rubix = IRCBot.new( "Rubix", "blah", "blah" )
#rubix.triggers[:join] = Array.new
#rubix.on_join { |bot, chan|
#    bot.say "suck", chan
#}
#rubix.on_join %{
#    say "Hi!", channel
#}
rubix.loadmod( SpamBot )
rubix.connect( "nbtsc.org", 6667, ["#rubixtest"] )



class Rubix < IRC::Client::Responder
    on_join :spam, :eggs
    on_action :eggs
    
    def spam
        say "Wazzup, #{nick}"
    end
    
    def eggs
        add_user_info :nick => nick, :eggs => 1, :action => :increment
        say "YOU LIKE PIGGIES"
    end
    
end