#encoding:utf-8
require 'flickraw'
require 'yaml'
require 'thread'
require 'logger'
require 'fileutils'

#### define logger

class Logger
  def format_message(level, time, progname, msg)
    #\e[0m = reset color(text) , \e[0;32m = Yellow(text)
    return "\e[0;32m#{level} #{time.strftime("%Y-%m-%d %H:%M:%S.%2N")}-- #{msg}\e[0m\n"
  end
end

class MultiLogger
  def initialize(*targets)
    @targets = targets
  end
  def write(*args)
    @targets.each{|t|t.write(*args)}
  end
  def close
    @targets.each{|t|t.close}
  end
end

#### main

class FlickrCatz
  DEFAULT_SETTINGS = {
    :api_key       => "2d9c3ceece371c4ac2914b2eb8cb4862",
    :api_secret    => "2103c83fddafdbb1",

    :auth_file     => 'flickr_catz_auth.yaml',
    :thread_pool   => 6,

    :base_path     => nil,
    :filter        => "*",
    :uploaded_prefix => "uploaded_",

    :log           => "flickr_catz.log"
  }
  def initialize(options = nil)
    @settings = Marshal.load(Marshal.dump(DEFAULT_SETTINGS)) #deep_clone
    
    if(options.is_a?(String))
      @settings[:base_path] = options
    elsif(options.is_a?(Hash))
      @settings = @settings.merge(options)
    end
    
    @logger = Logger.new(MultiLogger.new(STDOUT,File.open("#{@settings[:base_path]}#{@settings[:log]}" , 'a')))
    
    unless @settings[:base_path]
      logger("no base_path , Quit and return nil")
      raise "no base_path , Quit and return nil"
    end
    
    FlickRaw.api_key = @settings[:api_key]
    FlickRaw.shared_secret = @settings[:api_secret]
    
    @files_queue = Queue.new
    @thread_pool = []
    @connec_pool = []
    @auth_token  = nil

    @flickr = try_auth #@flickr for global , not for thread << race condition

    logger("auth success!!" , nil , :info)
    
    return self
  end
  
  def go!
    photosets = @flickr.photosets.getList
    init_photosets = []
    
    Dir.glob("#{@settings[:base_path]}/*").sort.each do |upload_folder|
      upload_folder = upload_folder.gsub(/\/{2,}/,'/') # "//123////123//" => "/123/123/"
      next if !File.directory?(upload_folder) || !upload_folder.match(/.*\/\d{4,8}.+/)
      upload_folder = File.basename(upload_folder)
      
      #find photo_set
      photoset_id = nil
      photosets.each do |set|
        if set["title"] == upload_folder
          photoset_id = set["id"]
          break
        end
      end

      #push to queue or initialize photosets
      Dir.glob("#{@settings[:base_path]}/#{upload_folder}/#{@settings[:filter]}").sort.each do |file_name|
        file_name = file_name.gsub(/\/{2,}/,'/')
        next if !File.file?(file_name) || file_name.match(/.*\/#{@settings[:uploaded_prefix]}.*/) || !file_name.match(/.*\.(jpg|gif|bmp|png)\z/i)
        file_name = File.basename(file_name)
        
        folder = "#{@settings[:base_path]}#{upload_folder}/"

        #create photo_set , upload now
        unless photoset_id
          photo_id = upload(@settings[:thread_pool] , [nil , folder , file_name])
          photoset_id = @flickr.photosets.create(:title => upload_folder , :primary_photo_id => photo_id)["id"]
        else
          @files_queue.push([photoset_id , folder , file_name])
        end
      end
    end
    
    while !@files_queue.empty?
      @settings[:thread_pool].times do |i|
        if !@thread_pool[i] || !@thread_pool[i].status
          @thread_pool[i] = Thread.new do
            upload(i)
          end
        end
      end
      sleep 0.1
    end
    
    begin
      thread_process_check = true
      @thread_pool.each do |thread|
        if thread.status
          thread_process_check = false
          sleep 0.1
          break
        end
      end
    end while !thread_process_check

    logger("====== [ Upload FINISHED ] ======" , nil , :info)
  rescue Exception => e
    logger("upload failed[go!]" , e)
  end
  
  private
  
  def logger(descript , e = nil , level = :error)
    @logger.send(level,descript)
    @logger.send(level,e.backtrace.unshift("#{e.message} [#{e.class}]").join("\n  ==> ")) if e
  end
  
  def get_auth_setting
    @auth_token = YAML.load(File.open(@settings[:auth_file]).read)
  rescue Errno::ENOENT => e
    logger("can't load flickr auth token , try to auth" , nil , :info)
  rescue Exception => e
    @auth_token = nil
    logger("fail to open #{@settings[:auth_file]}" , e)
    return false
  end
  
  def save_auth_setting
    File.open(@settings[:auth_file],'w'){|f|f.write(YAML.dump(@auth_token))} if @auth_token
  rescue Exception => e
    logger("fail to save #{@settings[:auth_file]}" , e)
    return false
  end
  
  def try_auth
    flickr = FlickRaw::Flickr.new
    auth_tested = false
    get_auth_setting
    while !@auth_token || !auth_tested
      if @auth_token
        flickr.access_token = @auth_token[:access_token]
        flickr.access_secret = @auth_token[:access_secret]
        begin
          auth = flickr.test.login
          if auth
            puts "Logged in #{auth.username}"
            auth_tested = true
          else
            @auth_token = nil
            auth_tested = false
            save_settings = true
          end
        rescue Exception => e
          @auth_token = nil
          auth_tested = false
          save_settings = true
          logger("try login fail" , e)
        end
      end

      if !@auth_token
        token = flickr.get_request_token
        auth_url = flickr.get_authorize_url(token['oauth_token'], :perms => 'delete')

        puts "Open URL in browser : #{auth_url}"
        puts "copy paste the digitals in here to authentication or type anything to Quit."
        print '[DDD-DDD-DDD] : '
        verify = gets.strip
        unless verify.match(/\A\d{3}\-\d{3}\-\d{3}\z/)
          puts "not match verify code format ==> Quit"
          abort
        end
        begin
          flickr.get_access_token(token['oauth_token'], token['oauth_token_secret'], verify)
          @auth_token = {:access_token => flickr.access_token , :access_secret => flickr.access_secret}
          auth_tested = true
          save_auth_setting
          puts 'loggin ed'
        rescue FlickRaw::OAuthClient::FailedResponse => e
          logger("Authentication failed" , nil , :info)
        rescue Exception => e
          logger("Authentication failed" , e)
        end
      end
    end
    return flickr
  end
  
  def upload(index , file_set = @files_queue.pop)
    flickr = @connec_pool[index] = try_auth if !(flickr = @connec_pool[index])
    
    photoset_id , folder , file_name = file_set
    
    photo_id = flickr.upload_photo("#{folder}#{file_name}")
    
    FileUtils.mv("#{folder}#{file_name}", "#{folder}#{@settings[:uploaded_prefix]}#{file_name}")
    
    add_photo_to_photoset(flickr , photo_id , photoset_id) if photoset_id
    logger("UPLOADED[#{index}] [left => #{@files_queue.length}] : #{folder}#{file_name}" , nil , :info)
    
    return photo_id
  rescue Exception => e
    retry_count = 0 if !local_variables.include?(:retry_count) || !retry_count
    if (retry_count += 1) <= 3 # retry 3 times
      logger("UPLOAD-RETRY[#{index}] [left => #{@files_queue.length}] : #{folder}#{file_name}" , nil , :info)
      logger("upload failed[#{index}] : #{folder}#{file_name} => retry(#{retry_count})" , e)
      retry
    else
      logger("upload failed[#{index}] : #{folder}#{file_name} => fail retry" , e)
    end
  end
  
  def add_photo_to_photoset(flickr , photo_id , photoset_id)
    flickr.photosets.addPhoto(:photoset_id => photoset_id , :photo_id => photo_id)      
  rescue Exception => e
    logger("add photo to set fail , maybe photo already in set" , e)
  end
end
