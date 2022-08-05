#!/usr/bin/perl -w

#######################################
# Magestic Management
# This script handles vacation auto responding.  It checks to see if the user has an 
# email in their vacation folder and then sends the email as a response to the 
# current email.  It also checks if it has sent an out of office message recently.
#######################################

use File::stat;
use Time::localtime;
use File::Touch;

my $g_UserName = $ARGV[0];
my $g_Domain = $ARGV[1];
my $g_ReplyTo = $ARGV[2];
my $g_ReplyPath = $ARGV[3];
my $g_From = $ARGV[4];
my $g_Subject = $ARGV[5];
my $g_MessageId = $ARGV[6];
my $g_References = $ARGV[7];
my $g_Precedence = $ARGV[8];

# Set the reply delay to 4 hours.  We'll autorespond if we haven't
# sent an out of office auto reply to the same user in more than 
# four hours.
my $g_ReplyDelay = 4 * 60 * 60;
#my $g_ReplyDelay = 5;

#open(my $debug, '>>', "/tmp/zzz-sieve");
#print $debug "---------------\n";
#print $debug "g_UserName = $g_UserName\n";
#print $debug "g_Domain = $g_Domain\n";
#print $debug "g_ReplyTo = $g_ReplyTo\n";
#print $debug "g_ReplyPath = $g_ReplyPath\n";
#print $debug "g_Subject = $g_Subject\n";
#print $debug "g_MessageId = $g_MessageId\n";
#print $debug "g_References = $g_References\n";

#######################################
# This function checks if this email
# contains an address that we should 
# autorespond to.  We don't want to respond
# to system messages or noreply messages.
#
# do not reply if Precedent field has a
# value with "list", "junk", "bulk"
# or if address doesn't have address
# or has <> in address
#######################################

#Old

#sub ValidRespondEmail {
#  my ($from) = @_;
#  my $invalid = (($from =~ /root\@majesticmanagement.ca/) or ($from =~ /no[-_]?reply\@/) or ($from =~ /do[-_]?not[-_]?reply\@/)); 
#  return not($invalid);
#}

#New
sub ValidRespondEmail{
   my ($from, $precedence) = @_;
   my $invalid = (($from =~ /root\@majesticmanagement.ca/) or
	   ($from =~ /no[-_]?reply\@/) or
	   ($from =~ /do[-_]?not[-_]?reply\@/) or 
	   ($precedence =~ /\b(junk|bulk|list)\b/));
     
   return not($invalid);
}


#my $tmp = "root\@majesticmanagement.ca";
#print "ValidRespondEmail($tmp) = " . ValidRespondEmail($tmp) . "\n";
#print "ValidRespondEmail('root\@majesticmanagement.ca') = " . ValidRespondEmail('root@majesticmanagement.ca') . "\n";
#print "ValidRespondEmail('noreply\@amazon.ca') = " . ValidRespondEmail('noreply@amazon.ca') . "\n";
#print "ValidRespondEmail('no-reply\@amazon.ca') = " . ValidRespondEmail('no-reply@amazon.ca') . "\n";
#print "ValidRespondEmail('bob\@amazon.ca') = " . ValidRespondEmail('bob@amazon.ca') . "\n";
#exit 0;


######################################
# This function grabs the first file it can find
# in the users's vacation email folder that is not
# marked for deletion and returns it.  If it cannot
# find a file, then it returns "".
#######################################
sub GetVacationFile {
   my ($username, $domain) = @_;

   my @files = glob "/var/spool/mail/vhosts/$domain/$username/.Vacation/cur/*";
   my $file = "";

   # See if we found a file
   if (scalar(@files) == 0) {
      #print $debug "Couldn't find any vacation files\n";
   } else {
      # Let's see which file we want to use.  If it has a T flag on the end, then
      # it is deleted and we don't want it.
      foreach my $element (@files) {
	      #print $debug "Checking file=$element\n";
         if ($element =~ /,*T[^,]*/) {
            # don't want this one.
         } else {
           $file = $element;
	   #print $debug "Found $file\n";
           last;
         }
      }
   }

   return $file;

}

#Test GetVacationFile
#print "Vacation file = (" . GetVacationFile( "voicemail", "majesticmanagement.ca" ) . ")\n";
#exit 0;
#######################################


#######################################
# Takes the from address and the reply to address.
# If there is a reply-to address, it returns that
# otherwise it returns the to address.
#
# Old
#######################################
sub GetReplyTo {
   my ($from, $replyto) = @_;

   # If we don't have a valid reply-to address, then use
   # the from (which comes from the From: header 
   if ( !( $replyto =~ /([a-zA-Z0-9!#$%&'\*\+=\?^_`{\|}\~-]+@[a-zA-Z0-9._-]+)/ )) {
       $replyto = $from;
   } 

   $replyto =~ /([a-zA-Z0-9][-a-zA-Z0-9!#\$.%&'\*\+=\?^_`{\|}\~]*@[a-zA-Z0-9._-]+)/;
   $replyto = $1;
   
   return $replyto;
}
 
# Test GetReplyTo
#my $ret = GetReplyTo( 'bob@majesticmanagement.ca ', '<delme@majesticmanagement.ca>');
#my $ret = GetReplyTo( 'bob@majesticmanagement.ca ', 'bob');
#print 'Reply-To = (';
#print $ret;
#print ")\n";
#exit 0;
#######################################


#######################################
# Takes the reply-path address.
# If there is not a reply-path, it takes
# the reply-to address.
# Otherwise it returns a from address.
# 
# (It should be possible to provide
# feedback to the person operating the
# responder.)
#######################################


sub GetReplyPath{
   my ($replyto, $replypath, $from) = @_;

   # If reply-path does not exist - we use
   # reply-to addres
   if(!($replypath =~/([a-zA-Z0-9!#$%&'\*\+=\?^_`{\|}\~-]+@[a-zA-Z0-9._-]+)/ )){
       $replypath = $replyto;

       # If reply-to does not exist - we use
       # the from address
       if(!($replypath =~ /([a-zA-Z0-9!#$%&'\*\+=\?^_`{\|}\~-]+@[a-zA-Z0-9._-]+)/)){
           $replypath = $from   
       }
   }
   
   return $replypath;
}


#######################################


#######################################
# Returns true if we need to auto reply
# Returns false if we have already replied
#######################################
sub NeedAutoReply {
   my ($user_name, $domain, $replyto) = @_;
   my $index_file = "/var/spool/vacation/$user_name\@$domain/$replyto";

   # check if the user folder exists
   if (!(-e "/var/spool/vacation/$user_name\@$domain")) {
      # make the folder
      mkdir "/var/spool/vacation/$user_name\@$domain";
   }

   # check if the index exists for this user/replyto combo
   if (!(-e $index_file)) {
      # File does not exist
      # Create an index
      touch($index_file);
      return 1;

   } else {
      # Read the modification time for the file
      if ((stat($index_file)->mtime + $g_ReplyDelay) < time()) {
         # We need to update the mtime on the index file
         touch($index_file);
         return 1;
      } else {
         # We've got an index file and it doesn't need updating
         # We don't need to auto reply
         return 0;
      }
   }
}

#print "NeedAutoReply=" . NeedAutoReply( "bob", "majesticmanagement.ca", 'voicemail@majesticmanagement.ca' ) . "\n"; 
#exit 1;
#######################################

  
#######################################
# This function sends the auto reply 
# message.  It returns 1 if successful
# and 0 otherwise.
#######################################
sub SendAutoReply {
   my ($vacation_file, $reply_to, $message_id, $references, $subject) = @_;
   my $ret = 1;
   my $from;
   my $clean_from;

   if (open(my $in, "<:encoding(utf8)", $vacation_file)) {
      
      # strip out all headers before the MIME-Version header
      my $row;

      while ($row = <$in>) {
         # Search for a From line in the autorespond email
         # We'll use this line for the From: header in the 
         # auto respond email.
         if ($row =~ /^From: /) {
            $row =~ s/^From: //;
            chomp $row;
            $from = $row;
         } elsif ($row =~ /^MIME-Version:/) {
            last;
         }
      }

      my $in_reply_to = $message_id;
      # Let's set up the references
      chomp $message_id;
      chomp $references;
      $references = $references . " " . $message_id;
      $clean_from = GetReplyTo($from,$from);

      # Let's pick a new message id
      $message_id = "<" . time() . ".$clean_from>";


      if (open (MAIL, "|/usr/sbin/sendmail -t -f $clean_from")) {
         print MAIL "To: $reply_to\n";
         print MAIL "From: $from\n";

         # Message-ID, In-Reply-To, and References are needed for threaded email readers.
         # We want our autoresponse to by tied to the same thread in the 
         # user's inbox.
         print MAIL "Message-ID: $message_id\n";

         # Only issue an In-Reply-To header if there was a message id
         if ($in_reply_to =~ /<.*>/) {
            print MAIL "In-Reply-To: $in_reply_to\n";
         }

         # Only issue a References header if we have references
         if ($references =~ /<.*>/) {
            print MAIL "References: $references\n";
         }

         print MAIL "Subject: Out Of Office Notice: $subject\n"; 

         # Row should be MIME_Version:
         print MAIL "$row";

         while (my $row = <$in>) {
            print MAIL "$row";
         }
 
         close (MAIL);
         $ret = 1;

      } else {
         $ret = 0;
      }
      close ($in);
   } else {
      $ret = 0;
   }
   
   return $ret;         
}

#SendAutoReply( 
#    GetVacationFile( "voicemail", "majesticmanagement.ca"), 
#    GetReplyTo( 'bob@majesticmanagement.ca', 'bob'),
#    'voicemail@majesticmanagement.ca', 
#    "<abc>", "<123>", "This is a test!" );
#######################################


#######################################
# Main function
#######################################

my $g_VacationFile = GetVacationFile($g_UserName, $g_Domain);
if ("" eq $g_VacationFile) {
   # There is no vacation file, so delete the user from the spool
   # check if the user folder exists
   if ((-e "/var/spool/vacation/$g_UserName\@$g_Domain")) {
	   #print $debug "executing command /usr/bin/rm -rf /var/spool/vacation/$g_UserName\@$g_Domain\n";
      system("rm -rf /var/spool/vacation/$g_UserName\@$g_Domain");
      #print $debug "finished rm\n";
   }
} #else {
   #print $debug "Found Vacation File: ($g_VacationFile)\n";
   # We have a vacation file
   #my $ReplyTo = GetReplyTo( $g_ReplyPath, $g_ReplyTo );
   #if (ValidRespondEmail($ReplyTo)) {
	   # if (NeedAutoReply( $g_UserName, $g_Domain, $ReplyTo)) {
	   # SendAutoReply( $g_VacationFile, $ReplyTo,  $g_MessageId, 
	      # #       $g_References, $g_Subject ); 
#	#}
#      #}
else {
    #print $debug "Found Vacation File: ($g_VacationFile)\n";
    # We have a vacation file
    my $ReplyPath = GetReplyPath( $g_ReplyTo, $g_ReplyPath, $g_From);
    if (ValidRespondEmail($ReplyPath, $g_Precedence)) {
       if (NeedAutoReply( $g_UserName, $g_Domain, $ReplyPath)) {
          SendAutoReply( $g_VacationFile, $ReplyPath,
		         $g_MessageId,
                         $g_References,
			 $g_Subject );
       }
    }

}

#close ($debug);

exit 0;   
