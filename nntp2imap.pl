# nntp2imap: A hack Perl script in the vein of rss2imap that downloads 
# messages from NNTP and puts them in an IMAP directory
# Copyright (C) 2011 Syntactic Vexation

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#!/usr/bin/perl

use warnings;
use strict;

use IO::Socket::SSL;
use Mail::IMAPClient;
use Net::NNTP;

use constant NEWS_PARENT_DIR => "News";

sub getMessagesForGroup {
	my $nntp = shift or die $!;
	my $group = shift or die $!;
	my $start_id = shift;
	my $end_id = shift;
	my $imap = shift;

	my @messages;

	for (my $i=$start_id; $i<=$end_id; $i++) {
		my $msg_data;
		my @article = $nntp->article($i);

		my $body = "";
		my $header = "";
		my $in_header = 1;

		foreach my $first (@article) {
			foreach my $second (@{$first}) {
				if ($in_header) {
					if ($second eq "\n") {
						$in_header = 0;
					} else {
						$header .= $second;
					}
				} else {
					$body .= $second;
				}
			}
		}

		$msg_data->{'header'} = $header;
		$msg_data->{'body'} = $body;

		if ($body ne "") {
			push(@messages,$msg_data);
			emailNewsMsg($imap, $group, $msg_data);
		}

	}

	return @messages;
}

sub createNewsDirs {
	my $imap = shift or die $!;
	my @newsgroups = @{shift()} or die $!;

	my $name;

	if (!$imap->exists(NEWS_PARENT_DIR)) {
		$imap->create(NEWS_PARENT_DIR) or die "Could not create Newsgroups folder: $@\n";
		$imap->subscribe(NEWS_PARENT_DIR);
	}	

	foreach (@newsgroups) {
		$name = $_->{'name'};
		$name =~ s/\./\-/g;

		if (!$imap->exists(NEWS_PARENT_DIR.".".$name)) {
			$imap->create(NEWS_PARENT_DIR.".".$name) or die "Could not create $name: $@\n";
			$imap->subscribe(NEWS_PARENT_DIR.".".$name);
		}
	}
}

sub emailNewsMsg {
	my $imap = shift or die $!;
	my $group_name = shift or die $!;
	my %newsMsg = %{shift()} or die $!;

	my $msg_text = $newsMsg{'header'};
	$msg_text .= "Reply-To: $group_name\n";
	$msg_text .= "\n"; # end of headers

	$msg_text .= $newsMsg{'body'};

	$group_name =~ s/\./\-/g;

	$imap->append_string(NEWS_PARENT_DIR.".".$group_name, $msg_text);
}

sub readConf {
	my %config;

	open(CONFIG, "</opt/nntp2imap/nntp2imap.conf") or die $!;

	while (<CONFIG>) {
		if (/(.*) = (.*)$/) {
			$config{$1} = $2;
		}
	}

	close(CONFIG);

	return %config;
}


# main()

my %config = readConf();

open(HISTORY_R, "</opt/nntp2imap/.nntp2imap_history") or die $!;

my @newsgroups;

while (<HISTORY_R>) {
	my $newsgroup = {};

	if (/(.*?)\s(.*)/) {
		$newsgroup->{'name'} = $1;
		$newsgroup->{'first_msg'} = $2 + 1;
	} else {
		print;
		die "Misconfigured history file!";
	}

	push(@newsgroups, $newsgroup);


}

close(HISTORY_R);


my %imap_args;
$imap_args{'User'} = $config{'imap_username'};
$imap_args{'Password'} = $config{'imap_password'};
$imap_args{'Socket'} = IO::Socket::SSL->new(Proto => 'tcp', PeerAddr => $config{'imap_server'}, PeerPort => 993,);


my $imap = Mail::IMAPClient->new(%imap_args) or die "Cannot connect $@";

#$imap->Debug(1);

createNewsDirs($imap, \@newsgroups);

my %nntp_options;
#$nntp_options{'Debug'} = 10;

my $nntp;

if ($nntp = Net::NNTP->new($config{'nntp_server'},%nntp_options)) {
#$nntp->authinfo($config{'nntp_username'}, $config{'nntp_password'});

# see what's new
foreach my $newsgroup (@newsgroups) {
	my ($num_of_articles, $first_article, $last_article) = 
		$nntp->group($newsgroup->{'name'}) or die $!.$newsgroup->{'name'};

	if ($newsgroup->{'first_msg'} == 0) {
		$newsgroup->{'first_msg'} = $first_article;
	}

	$newsgroup->{'last_msg'} = $last_article;

	my @group_messages = getMessagesForGroup($nntp, $newsgroup->{'name'},
		$newsgroup->{'first_msg'}, $newsgroup->{'last_msg'}, $imap);
}	

$nntp->quit;
}

$imap->disconnect();

if ($nntp) {
	open(HISTORY_W, "+>/opt/nntp2imap/.nntp2imap_history") or die $!;

	foreach my $newsgroup (@newsgroups) {
		print HISTORY_W $newsgroup->{'name'}, "\t", $newsgroup->{'last_msg'}, "\n";
	}

	close(HISTORY_W);
}
