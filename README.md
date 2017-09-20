# Twitch to Slack (Perl)
Perl script sending slack a message when twitch channel(s) starts or stops streaming

I wanted a simple script that i could cron to poll twitch for streamers to post to our slack channel.

I originally had it posting attachments, and if you do that, you don't need Image::Resize or Image::Grab, you can comment out that part plus the subs that relate to the image resizing. The problem i found was that the images pulled from Twitch were not rendering in slack when using the url for icon_url, so i had to resize them to 36x36 to make them pop up.

Make sure to create a directory called '/boticons' where the script lives. you may have to adjust the server url if you have it anywhere else other than the top html level. i happened to put this into a /twitch folder and used a .htaccess file to make sure no one could see a directory listing from the web.

.htaccess
  Options -Indexes 

Dependencies:
---------------
LWP::UserAgent  
Data::Dumper  
REST::Client  
DateTime::Format::ISO8601  
JSON::XS  
Image::Resize  
Image::Grab  

