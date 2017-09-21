#!/usr/bin/perl

use strict;
use LWP::UserAgent;
use REST::Client;
use JSON::XS;
use YAML::XS 'LoadFile';

# Load in config
# -------------------------------------------------
my $config = LoadFile('/path/to/config.yml');

my $slack_bot_token   = $config->{'slack_bot_token'};
my $twitch_client_id  = $config->{'twitch_client_id'};
my $filename          = $config->{'filename'};
my $bot_name          = $config->{'bot_name'};
my $slack_channel     = $config->{'slack_channel'};
my $use_attachments   = $config->{'use_attachments'};
my @streamers         = @{$config->{'streamers'}};

# Run main subroutine
main();


#=======================================
# Start Main
#=======================================
sub main {

  # Streamer containers
  # -------------------------------------------------
  my $streamer_hash = {};
  my $textfile_hash = {};

  foreach my $name (@streamers){
    # first we'll set all the streamers inactive
    $streamer_hash->{$name}->{'stream_id'} = 0; 
  }

  # Now we'll pull from Twitch and see which ones are active 
  # -------------------------------------------------
  my $live_streams = &get_stream_status({ name => join(',', @streamers, limit => scalar(@streamers)) });

  for my $live (@$live_streams) {
    if($live->{'_id'}){
      # Now lets add the current stream_id and info to the hash
      $streamer_hash->{lc($live->{'channel'}->{'name'})} = {   
          'stream_id'     => $live->{'_id'},
          'streamer_name' => $live->{'channel'}->{'name'},
          'name'          => lc($live->{'channel'}->{'name'}),
          'display_name'  => $live->{'channel'}->{'display_name'},
          'game'          => $live->{'channel'}->{'game'},
          'status'        => $live->{'channel'}->{'status'},
          'url'           => $live->{'channel'}->{'url'},
          'logo'          => $live->{'channel'}->{'logo'}
      };
    }
  }

  # Gather our list of saved active broadcasters from our local text file
  # -------------------------------------------------
  open(my $fh, '<encoding(UTF-8)', $filename) or die "Failed to open file '$filename'";
  while(my $row = <$fh>){
    chomp $row;
    my ($name, $stream_id) = split(/:/, $row);

    # If they have a stream_id then they're considered "active"
    if($streamer_hash->{$name} && $stream_id > 0){

      # So this hash will be our "active" list
      $textfile_hash->{$name}->{'stream_id'} = $stream_id;
    }
  }


  # So now we'll cycle through our streamer hash, and 
  # figure out what status they're in.
  # -------------------------------------------------
  foreach my $name (keys %$streamer_hash){
    my $individual_hash   = $streamer_hash->{$name};
    my $stream_id         = $streamer_hash->{$name}->{'stream_id'};
 
    # If they're already in the text file, just make sure the id's are the same. 
    if($textfile_hash->{$name} && $textfile_hash->{$name}->{'stream_id'} == $stream_id){
      # Do Nothing - Now we can just ignore this one, they were active, and are still active.
    }
    elsif($textfile_hash->{$name} && $stream_id == 0){
      # They went offline. remove them from the active hash if they're in it.
      delete $textfile_hash->{$name};

      # we'll also send a post saying they went offline. 
      &stopped_streaming($name);  
    }
    else{
      # These guys were not in the textfile of active streamers.
      # if the stream id is not zero, they must be streaming now.
      if($stream_id > 0){ 
        # First we'll add them to the textfile hash
        $textfile_hash->{$name}->{'stream_id'} = $stream_id;

        unless($use_attachments){
          # need to create a 36x36 icon for the thumbnail  but twitch 
          # only has these sizes : 600x600, 300x300, 150x150, 70x70, 50x50, 28x28
          my $thumb_url = $individual_hash->{'logo'};
          $thumb_url =~ s/300x300/50x50/;

          if($thumb_url){
            $individual_hash->{'thumb_url'} = $thumb_url;
          }
        }

        # Now send off a notification to slack
        &started_streaming($individual_hash);
      }
      else{
        # Do Nothing - Again we do nothing, because they are inactive. 
      }
    }
  }

  # Finally, we'll overwrite our old textfile, with the new active streamers.
  # -------------------------------------------------
  open(my $fh, '>', $filename);
  foreach my $name (sort keys %$streamer_hash){
    my $stream_id = $streamer_hash->{$name}->{'stream_id'};
    if($stream_id > 0){
      print $fh lc($name) . ":" . $stream_id . "\n";
    }
  }
  close $fh;
}


#=======================================
# Start Subs
#=======================================
sub get_stream_status {
  my($args) = shift;

  my $name = $args->{'name'} || undef;
  return(undef) unless($name);

  my $query_string = '?channel=' . $name;
  if($args->{'limit'}) {
    $query_string .= '&limit=' . $args->{'limit'};
  }

  my $data = &do_request('streams' . $query_string);
  return(undef) unless($data);

  if($data->{'_total'} > 0) {
    return($data->{'streams'});
  }
  return([]);
}

sub do_request {
  my($uri) = shift;

  my $uri_base = 'https://api.twitch.tv/kraken/';
  my $client = REST::Client->new();
  $client->addHeader('Client-ID', $twitch_client_id);
  $client->addHeader('Accept', 'application/vnd.twitchtv.v3+json');
  $client->setTimeout(10);
  $client->GET($uri_base . $uri);

  if($client->responseCode() == 200) {
    my $content = decode_json($client->responseContent());
    return($content);
  }
  return(undef);
}

sub stopped_streaming {
  my ($name) = shift;

  # Now we'll post to slack
  my $ua = LWP::UserAgent->new();
  my $res = $ua->post(
    'https://slack.com/api/chat.postMessage',
    {
      token    => $slack_bot_token,
      as_user  => 'true',
      username => $bot_name,
      channel  => $slack_channel,
      text     => $name . ' has stopped streaming'
    }
  );
}

sub started_streaming {
  my ($hash) = shift;

  # I've included two different ways to post. 
  # 1. Set $use_attachments = 1 if you want it to post with attachments.
  # 2. Set $use_attachments = 0 if you don't want it to post with attachments.

  my $post_hash;

  if($use_attachments){
    $post_hash = {
      token    => $slack_bot_token,
      as_user  => 'true',
      username => $bot_name,
      channel  => $slack_channel,
      text     => $hash->{'display_name'} . ' has started streaming: ' . $hash->{'game'},
      attachments => encode_json([
        {
          color => '#428bca',
          text => $hash->{'status'},
          title => $hash->{'url'},
          title_link => $hash->{'url'},
          thumb_url  => $hash->{'logo'}
        }
      ])
    };
  }
  else{
    $post_hash = {
        token         => $slack_bot_token,
        as_user       => 'true',
        username      => $bot_name,
        channel       => $slack_channel,
        text          => $hash->{'display_name'} . ' has started streaming: ' . $hash->{'status'} . ' (' . $hash->{'game'} .")\n" . $hash->{'url'},
        attachments   => [{}]
    };

    if($hash->{'thumb_url'}){
      $post_hash->{'as_user'}   = 'false';
      $post_hash->{ 'icon_url'} = $hash->{'thumb_url'};
    }
  }

  # Now we'll post to slack
  my $ua = LWP::UserAgent->new();
  my $res = $ua->post( 'https://slack.com/api/chat.postMessage', $post_hash);
}
