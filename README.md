# Twitch to Slack (Perl)
Perl script sending slack a message when twitch channel(s) starts or stops streaming

I wanted a simple script that i could cron to poll twitch for streamers to post to our slack channel.

I originally had it posting attachments, but i felt it was just too big of a post, and wanted something cleaner, so but i left it in in case others might want it.

Dependencies:
---------------
LWP::UserAgent  
REST::Client  
JSON::XS  
YAML::XS 'LoadFile'  


