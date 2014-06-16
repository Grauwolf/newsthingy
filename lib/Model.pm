#!/usr/bin/perl

package Model;

use strict;
use warnings;
use v5.10;

$ENV{HTTPS_DEBUG}=1;
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;

use FindBin qw($RealBin);

use Date::Parse;
use Log::Log4perl qw(:easy);
use Mojo::ByteStream 'b';
use XML::Feed;

Log::Log4perl->easy_init( $INFO );

use ORLite {
    file    => "$RealBin/news.db",
    unicode => 1,
    cleanup => 'VACUUM',
    create  => sub {
        my $dbh = shift;

        $dbh->do(
            'CREATE TABLE categories (
            id   INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
            )'
        );

        $dbh->do(
            'CREATE TABLE feeds (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            name             TEXT,
            url              TEXT NOT NULL UNIQUE,
            link             TEXT,
            category_id      INTEGER,
            last_update      INTEGER DEFAULT 0,
            active           INTEGER DEFAULT 1,
            description      INTEGER DEFAULT 1,
            update_frequency INTEGER DEFAULT 10800
            )'
        );

        $dbh->do(
            'CREATE TABLE items (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            pubDate     INTEGER NOT NULL,
            guid        TEXT NOT NULL UNIQUE,
            title       TEXT,
            author      TEXT,
            url         TEXT,
            feed_id     INTEGER NOT NULL,
            description TEXT,
            read        INTEGER NOT NULL DEFAULT 0,
            starred     INTEGER NOT NULL DEFAULT 0
            )'
        );


        my @categories = qw<news blog>;
        foreach ( @categories ) {
            $dbh->do( 'INSERT INTO categories (name) VALUES (?)', {}, $_ ); 
        }

        $dbh->do(
            'INSERT INTO feeds (name, url, category_id) VALUES (?, ?, ?)',
            {},
            'Perl Blogs', 'http://blogs.perl.org/atom.xml', 1
        ); 

        $dbh->do(
            'INSERT INTO feeds (name, url, category_id) VALUES (?, ?, ?)',
            {},
            'LWN.net', 'https://lwn.net/headlines/newrss', 1
        );  

        return 1;
    }
};

sub add_feed {
    my ( $self,
         $name,
         $url,
         $cat,
         $freq,
         $desc ) = @_;

     Model->do(
         'INSERT OR IGNORE INTO categories
         (name) VALUES (?)',
         {},
         $cat
     );

     Model->do(
         'INSERT OR IGNORE INTO feeds
         (name, url, category_id, update_frequency, description)
         VALUES (
            ?,
            ?,
            (SELECT id from categories where name = ?),
            ?,
            ?
         )',
         {},
         $name, $url, $cat, $freq, $desc 
     );
} 

sub delete_feed {
    my ( $self, $fid ) = @_;
    Model->do( 'DELETE FROM items WHERE feed_id = ?', {}, $fid );
    Model->do( 'DELETE FROM feeds WHERE id = ?', {}, $fid );
}

sub disable_feed {
    my ( $self, $fid ) = @_;
    Model->do( 'UPDATE FEEDS SET active = 0 WHERE id = ?', {}, $fid );
}

sub enable_feed {
    my ( $self, $fid ) = @_;
    Model->do( 'UPDATE FEEDS SET active = 1 WHERE id = ?', {}, $fid );
} 

sub get_feeds {
    my ( $fid ) = @_;

    my @feeds;
    if ( $fid ) {
        @feeds = Model::Feeds->select('WHERE id = ?', $fid);
    }
    else {
        @feeds = Model::Feeds->select('WHERE active = 1 ORDER BY name');
    } 

    return \@feeds;
}

sub update_feeds {
    my ( $self, $feed_id ) = @_;

    Model->commit_begin;

    foreach my $feed (
        @{ get_feeds( $feed_id ) }
    ) {
        my $fid  = $feed->id;
        my $desc = $feed->description;
        if (
            not $feed_id
            and (time - $feed->last_update) < $feed->update_frequency
        ) {
            next;
        }
        INFO 'getting ' . $feed->url;

        my $rss;
        eval {
            $rss = XML::Feed->parse(URI->new( $feed->url )) || next;
        }
        or do {
            next;
        };

        # check for no items
        if ( $rss->items == 0 ) {
            ERROR 'no feed items found in ' . $feed->url . ' bad feed?';
            next;
        }

        foreach my $item ($rss->entries) {
            my $ititle      = $item->title;
            my $ipubDate    = str2time( $item->issued ) || time;
            my $iurl        = $item->link;
            my $iauthor     = $item->author;
            my $iguid       = $item->id || $iurl;

            my $idescription;
            if ( $desc ) { $idescription = $item->content->body; }

            Model->do(
                'INSERT OR IGNORE INTO items
                (pubDate, guid, title, author, url, feed_id, description)
                VALUES (?, ?, ?, ?, ?, ?, ?)',
                {},
                $ipubDate,
                $iguid,
                $ititle,
                $iauthor,
                $iurl,
                $fid,
                $idescription
            );
        }

        Model->do(
            'UPDATE feeds set last_update = ?, link = ? WHERE id = ?',
            {},
            time, $rss->link, $fid
        );

        INFO 'done getting feed '. $feed->url;
    }

    Model->commit;
}


sub convert_time {
    my ($self, $time) = @_;
    my $days = int($time / 86400);
    $time -= ($days * 86400);
    my $hours = int($time / 3600);
    $time -= ($hours * 3600);
    my $minutes = int($time / 60);
    my $seconds = $time % 60;

    $days = $days < 1 ? '' : $days .'d ';
    $hours = $hours < 1 ? '' : $hours .'h ';
    $minutes = $minutes < 1 ? '' : $minutes . 'm ';
    $time = $days . $hours . $minutes . $seconds . 's';
    return $time;
}

1;
