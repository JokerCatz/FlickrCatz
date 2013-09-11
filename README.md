#FlickrCatz
- - -
FlickrCatz is a tool to upload image/video with flickr , multi thread & yaml settings & logger supported , set a UPLOAD_ROOT_PATH and subfolders be photosets , add a prefix filename when image/video is uploaded

use default Flickr API key is named FlickrCatz

#Useage
- - -
(TODO : alpha version not yet fix to gem , irb only now)

    > require './flickr_catz.rb'
    
    > flickr_catz = FlickrCatz.new('/home/test_user/photos') #UPLOAD_ROOT_PATH
    
     # INFO 2013-09-11 12:54:45.49-- can't load flickr auth token , try to auth
     # Open URL in browser : http://www.flickr.com/services/oauth/authorize?oauth_token=72157635478298024-007145dd0611f28d&perms=delete
     # copy paste the digitals in here to authentication or type anything to Quit.
    
    > [DDD-DDD-DDD] : #get to auth key (auto save auth token in [flickr_catz_auth.yaml] if success)
    
     # INFO 2013-09-11 13:01:20.11-- auth success!!
    
    > flickr_catz.go! #start_upload
    
     # INFO 2013-09-11 13:10:10.14-- UPLOADED[3] [left => 7] : /home/test_user/photos/IMG_20130727_173502.jpg
    
    ……

#Setting
- - -
    #set UPLOAD_ROOT_PATH only
    > settings = '/home/test_user/photos'
    
    #set configure
    > settings = {
    
      # flickr API key & secret 
      :api_key       => "2d9c3ceece371c4ac2914b2eb8cb4862",
      :api_secret    => "2103c83fddafdbb1",

      # save auth file when auth success
      :auth_file     => 'flickr_catz_auth.yaml',
      
      # thread pool size
      :thread_pool   => 4,

      # UPLOAD_ROOT_PATH
      :base_path     => nil,
      
      # file_name filter [bash]
      :filter        => "*",
      
      # uploaded filename prefix
      :uploaded_prefix => "uploaded_",

      # log_file (save in UPLOAD_ROOT_PATH)
      :log           => "flickr_catz.log"
    }
    
    > FlickrCatz.new(settings)
    
