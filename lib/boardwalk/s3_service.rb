# require 'sinatra/base'
=begin
# NOTE: This will most likely have to be in Rack so that requests using aws can
# be directed before being processed in sinatra.

# Here's what _why did...
# service() in this sense is defined to overwrite the default service behavior
# in camping. Basically, disect and encrypt the header so that it may be 
# checked against the user's signature.
  def service(*a)
    # Copy the header twice.
      @meta, @amz = ParkPlace::H[], ParkPlace::H[]
  # @env is an H containing the HTTP headers and server info.
      @env.each do |k, v|
          k = k.downcase.gsub('_', '-')
          @amz[$1] = v.strip if k =~ /^http-x-amz-([-\w]+)$/
  # @meta shouldn't be used since it is stuff sent by the user and not 
  # interpreted by S3 service.
          @meta[$1] = v if k =~ /^http-x-amz-meta-([-\w]+)$/
      end

      auth, key_s, secret_s = *@env.HTTP_AUTHORIZATION.to_s.match(/^AWS (\w+):(.+)$/)
      date_s = @env.HTTP_X_AMZ_DATE || @env.HTTP_DATE
      # NOTE: @input is for url encoded variables. @input.Signature looks for a
      #       signature in the url to use. Otherwise, it uses HTTP header.
      if @input.Signature and Time.at(@input.Expires.to_i) >= Time.now
          key_s, secret_s, date_s = @input.AWSAccessKeyId, @input.Signature, @input.Expires
      end
      uri = @env.PATH_INFO
      uri += "?" + @env.QUERY_STRING if ParkPlace::RESOURCE_TYPES.include?(@env.QUERY_STRING)
      canonical = [@env.REQUEST_METHOD, @env.HTTP_CONTENT_MD5, @env.HTTP_CONTENT_TYPE, 
          date_s, uri]
      @amz.sort.each do |k, v|
          canonical[-1,0] = "x-amz-#{k}:#{v}"
      end
      @user = ParkPlace::Models::User.find_by_key key_s
      if @user and secret_s != hmac_sha1(@user.secret, canonical.map{|v|v.to_s.strip} * "\n")
          raise BadAuthentication
      end

      s = super(*a)
      s.headers['Server'] = 'ParkPlace'
      s
  rescue ParkPlace::ServiceError => e
      xml e.status do |x|
          x.Error do
              x.Code e.code
              x.Message e.message
              x.Resource @env.PATH_INFO
              x.RequestId Time.now.to_i
          end
      end
      self
  end

  # Parse any ACL requests which have come in.
  def requested_acl
      # FIX: parse XML
      raise NotImplemented if @input.has_key? 'acl'
      {:access => ParkPlace::CANNED_ACLS[@amz['acl']] || ParkPlace::CANNED_ACLS['private']}
  end
=end
require 'sinatra/base'
require 'openssl'
require 'base64'
require 'hmac-sha1'

##
# TODO: Removed User class from this document once implementing database 
#       handler.
##
class User
  def initialize(key)
    @login = 'testuser'
    @key = key
  end
  
  def key
    @key
  end
  
  def login
    @login
  end
end

module Sinatra
  class Request
    module AWSHandler
    
    # module Helpers
      def aws_authenticate
        before {
          puts "Should do env loop."
          @env.each do |k, v|
            puts "Running env loop. (#{k}, #{v})"
            k = k.downcase.gsub('_', '-')
            @amz[$1] = v.strip if k =~ /^http-x-amz-([-\w]+)$/
          end
          date = (@env['HTTP_X_AMZ_DATE'] || @env['HTTP_DATE'])
          auth, key, secret = *@env['HTTP_AUTHORIZATION'].to_s.match(/^AWS (\w+):(.+)$/)
          # Might need to do some URL sniffing magic. Not sure if PATH_INFO will
          # cover URL encoded variables.
          # Regexp: /[\?|&](\w+)=(\w+)/
          uri = @env['PATH_INFO']
          uri += "?" + @env['QUERY_STRING'] if RESOURCE_TYPES.include?(@env['QUERY_STRING'])
          canonical = [@env['REQUEST_METHOD'], @env['HTTP_CONTENT_MD5'], @env['HTTP_CONTENT_TYPE'], date, uri]
          # @amz.sort.each do |k, v|
          #   canonical[-1,0] = "x-amz-#{k}:#{v}"
          # end
          content = []
          content << "START #{Time.now}\n"
          # PSEDUO: If the user sent secret string is equal to the user's 
          #         [encrypted] information from the server, user is clear.
          #         otherwise, user is not allowed.
          @user = User.new(key)
          server_key = hmac_sha1(options.s3secret, canonical.map{|v|v.to_s.strip} * "\n")
          if(secret == server_key)
            content << "Keys are IDENTICAL!\n"
          else
            content << "Keys are DIFFERENT!\n"
          end
          content << "END #{Time.now}\n\n"
          f = File.new("logs/service_dump.log", "a")
          f.syswrite content.to_s
          f.close
          # @user = Boardwalk::Models::User.find_by_key key
          @user = User.new(key)
          if @user and secret != server_key
            raise BadAuthentication
          end
        }
      end
      
      def hmac_sha1(key, s)
        return Base64.encode64(OpenSSL::HMAC.digest(OpenSSL::Digest::Digest.new("sha1"), key, s)).strip
      end
      
    end
  end
  register Request::AWSHandler
end