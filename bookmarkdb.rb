require './rubilicious.rb'

class BookmarkDB < IRC::Client::Responder
    URI_RE1 = %r{^((?:http|ftp)://[^:!"'() ]+) (?:--|#) (.+)}mi
    URI_RE2 = %r{^((?:http|ftp)://[^:!"'() ]+) (.+)}mi
    URI_RE3 = %r{^((?:http|ftp)://[^:!"'() ]+)\s*$}mi
    
    on_init do
        @@r = Rubilicious.new( "rubix", "ushipnine" )
    end
    
    on_privmsg do
        if message =~ /http:\/\/(?:www\.)?goatse\.cx/i
            smack nick
        elsif ( message =~ URI_RE1 )
            puts "posting bookmark on del.icio.us"
            uri = $1
            title = $2
            
            Thread.new do
                desc = find_desc( uri )
                if desc == nil # no description, use title for both
                    @@r.add( uri, title, title, nick )
                else # found a description, use it and title
                    @@r.add( uri, title, desc, nick )
                end
            end
            
        elsif ( message =~ URI_RE2 )
            puts "posting bookmark on del.icio.us"
            uri = $1
            title = $2
            
            Thread.new do
                desc = find_desc( uri )
                if desc == nil # no description and title may be weird (but use it anyway, for now)
                    @@r.add( uri, uri, title, nick )
                else # found description so use it instead of the possibly weird title
                    @@r.add( uri, desc, desc, nick )
                end
            end
            
        elsif ( message =~ URI_RE3 )
            puts "posting bookmark on del.icio.us"
            uri = $1
            
            Thread.new do
                desc = find_desc( uri )
                if desc == nil # no description and no title
                    @@r.add( uri, uri, "#{nick}'s link", nick )
                else # found a description, no title
                    @@r.add( uri, desc, desc, nick )
                end
            end
        end
    end
    
    def fetch( uri_str, limit = 10 )
        throw :yourmom if limit == 0

        response = Net::HTTP.get_response( URI.parse( uri_str ) )
        case response
            when Net::HTTPSuccess     then response
            when Net::HTTPRedirection
                # if it redirects to a movie or image or something
                # this needs to be fixed to just look at the
                # header mime-type information
                if response['location'] =~ /\.(?:jpg|jpeg|gif|png|tiff|mov|mp3|mp4|wmv|swf|avi)$/i
                    1
                else
                    fetch( response['location'], limit - 1 )
                end
        else
            response.error!
        end
    end
    
    def find_desc( uri )
        catch :yourmom do
            if uri !~ /\.(?:jpg|jpeg|gif|png|tiff|mov|mp3|mp4|wmv|swf|avi)$/i
                desc = fetch( uri )
                if desc.respond_to? :body
                    if fetch( uri ).body =~ /<title>(.+)<\/title>/mi
                        puts "Found the title for #{uri}, it's \"#{$1}\""
                        $1
                    end
                elsif desc == 1
                    "media"
                end
            else "media" end
        end
    end
end