#!/usr/bin/ruby -w

require 'ircclient.rb'
require 'bookmarkdb.rb'

class Rubix < IRC::Client::Responder
    on_join :spam, :eggs
    on_action :eggs
    
    def spam
        say "Wazzup, #{nick}"
    end
    
    def eggs
        #add_user_info :nick => nick, :tag => :eggs, :action => :increment
        if message =~ /snirks/ and rand(10) == 6
            say "YOU LIKE PIGGIES"
        end
    end
    
    on_say do        
        if message =~ /^spam/
            say "Llama!"
        end
        
        if message =~ /^who was (.+)/i
            if Users.data[$1]
                say "#{$1} was "
            end
        end
    end
end

rubix = IRC::Client::new
rubix.verbosity = 3
rubix.connect