#!/usr/bin/perl

use Mojolicious::Lite;

use DateTime;
use DateTime::Duration;
use Date::Parse;

BEGIN {
    use FindBin;
    use lib "$FindBin::Bin/lib";
}

require Model;

get '/' => 'index';

################################################################################
get '/empty' => sub {
################################################################################
    my $self = shift;
    $self->render( text => '' );
};

################################################################################
get '/feeds' => sub {
################################################################################
    my $self = shift; $self->redirect_to('/feeds/unread');
};

################################################################################
post '/feeds/add' => sub {
################################################################################
    my $self = shift;
    my $ref  = $self->req->headers->referrer || '/feeds/manage';

    my $name = $self->param('name');
    my $url  = $self->param('url');
    my $cat  = $self->param('category');
    my $freq = $self->param('frequency') || 60;
    my $desc = $self->param('desc');

    if ( $name and $url and $cat ) {
    }

    Model->add_feed(
        $name,
        $url,
        $cat,
        $freq,
        $desc
    );

    $self->redirect_to( $ref );
}; 

################################################################################
get '/feeds/manage' => sub {
################################################################################
    my $self = shift;

    $self->stash(
        feeds => [Model::Feeds->select('ORDER BY name ASC')]
    );

    $self->render('feeds_manage');
};

################################################################################
get '/feeds/:fid/update' => sub {
################################################################################
    my $self = shift;
    my $fid  = $self->param( 'fid' );
    my $ref  = $self->req->headers->referrer || '/feeds/unread';

    Model->update_feeds( $fid );
    
    $self->redirect_to( $ref );
}; 

################################################################################
get '/feeds/:fid/delete' => sub {
################################################################################
    my $self = shift;
    my $fid = $self->param( 'fid' );

    Model->delete_feed( $fid );
    
    $self->redirect_to( '/feeds/manage' );
};

################################################################################
get '/feeds/:fid/disable' => sub {
################################################################################
    my $self = shift;
    my $fid = $self->param( 'fid' );

    Model->disable_feed( $fid );
    
    $self->redirect_to( '/feeds/manage' );
};

################################################################################
get '/feeds/:fid/enable' => sub {
################################################################################
    my $self = shift;
    my $fid = $self->param( 'fid' );

    Model->enable_feed( $fid );
    
    $self->redirect_to( '/feeds/manage' );
}; 

################################################################################
get '/feeds/:date' => [date => qr/\d{4}-\d{2}-\d{2}/] => sub {
################################################################################
    my $self = shift;
    my $date = str2time( $self->param('date') );

    $self->redirect_to( '/feeds/' . $date . '/unread' );
};

################################################################################
get '/feeds/:date/all' => [date => qr/\d{4}-\d{2}-\d{2}/] => sub {
################################################################################
    my $self = shift;
    my $date = str2time( $self->param('date') );

    $self->stash(
        items => [Model::items->select('WHERE date = ? ORDER BY pubDate ASC', $date)]
    );
};

################################################################################
get '/feeds/:date/unread' => [date => qr/\d{4}-\d{2}-\d{2}/] => sub {
################################################################################
    my $self = shift;
    my $date = str2time( $self->param('date') );

    $self->stash(
        items => [Model::Items->select('WHERE date = ? AND read = 0 ORDER BY pubDate ASC', $date)]
    );
};

################################################################################
get '/feeds/:id' => [id => qr/\d+/] => sub {
################################################################################
    my $self = shift;
    my $id   = $self->param( 'id' );

    my %content;

    my $sql =
    'SELECT
      feeds.id AS feedid,
      feeds.name AS feedname,
      feeds.category_id AS catid,
      feeds.last_update AS lastupdate,
      feeds.update_frequency AS frequency,
      items.id AS itemid,
      items.title AS itemtitle,
      items.url AS itemurl,
      items.pubDate AS itempubDate,
      items.read AS itemread,
      categories.name AS catname
    FROM feeds
    JOIN items ON feeds.id = items.feed_id
    JOIN categories ON feeds.category_id = categories.id
    WHERE 
      items.feed_id = ?
    ORDER BY items.pubDate ASC';

    Model->iterate(
        $sql,
        $id,
        sub {
            my $feedid      = $_->[0];
            my $feedname    = $_->[1];
            my $catid       = $_->[2];
            my $lastupdate  = $_->[3];
            my $frequency   = $_->[4];
            my $itemid      = $_->[5];
            my $itemtitle   = $_->[6] || '<notitle>';
            my $itemurl     = $_->[7];
            my $itempubDate = $_->[8];
            my $itemread    = $_->[9];
            my $category    = $_->[10];

            my $nextupdate = int ( time - $lastupdate - $frequency ) * (-1);

            $content{ $category }{ $feedname }{ 'feedid' } = $feedid;
            $content{ $category }{ $feedname }{ 'nextupdate' } = Model->convert_time( $nextupdate );
            my $item = { 
                id      => $itemid,
                title   => $itemtitle,
                url     => $itemurl,
                pubDate => DateTime->from_epoch( epoch => $itempubDate ),
                read    => $itemread,
            };  
            push( @{ $content{ $category }{ $feedname }{ 'items' } }, $item );
        }
    );

    $self->stash(
        content => \%content,
    );

    $self->render('list_items'); 
}; 

################################################################################
get '/feeds/unread' => sub {
################################################################################
    my $self = shift;

    my %content;

    my $sql =
    'SELECT
      feeds.id AS feedid,
      feeds.name AS feedname,
      feeds.category_id AS catid,
      feeds.last_update AS lastupdate,
      feeds.update_frequency AS frequency,
      items.id AS itemid,
      items.title AS itemtitle,
      items.url AS itemurl,
      items.pubDate AS itempubDate,
      items.read AS itemread,
      categories.name AS catname
    FROM feeds
    JOIN items ON feeds.id = items.feed_id
    JOIN categories ON feeds.category_id = categories.id
    WHERE items.read = 0
    ORDER BY items.pubDate ASC';

    Model->iterate(
        $sql,
        sub {
            my $feedid      = $_->[0];
            my $feedname    = $_->[1];
            my $catid       = $_->[2];
            my $lastupdate  = $_->[3];
            my $frequency   = $_->[4];
            my $itemid      = $_->[5];
            my $itemtitle   = $_->[6] || '<notitle>';
            my $itemurl     = $_->[7];
            my $itempubDate = $_->[8];
            my $itemread    = $_->[9];
            my $category    = $_->[10];

            my $nextupdate = int ( time - $lastupdate - $frequency ) * (-1);

            $content{ $category }{ $feedname }{ 'feedid' } = $feedid;
            $content{ $category }{ $feedname }{ 'nextupdate' } = Model->convert_time( $nextupdate );
            my $item = { 
                id      => $itemid,
                title   => $itemtitle,
                url     => $itemurl,
                pubDate => DateTime->from_epoch( epoch => $itempubDate ),
                read    => 0,
            };  
            push( @{ $content{ $category }{ $feedname }{ 'items' } }, $item );
        }
    );

    $self->stash(
        content => \%content,
    );

    $self->render('list_items');
};

################################################################################
get '/flag/feed/:id/read' => sub {
################################################################################
    my $self = shift;
    my $id   = $self->param('id');
    my $ref  =  $self->req->headers->referrer || '/feeds';

    Model->do(
        'UPDATE items SET read = 1 WHERE feed_id = ? AND read = 0', {},
        $id
    );

    $self->redirect_to( $ref );
};

################################################################################
get '/item/:id' => sub {
################################################################################
    my $self = shift;

    my $id = $self->param('id');

    Model->do( 'UPDATE items set read = 1 WHERE id = ?', {}, $id );

    $self->stash(
        items => [Model::Items->select('WHERE id = ?', $id)]
    );

    $self->render( 'item_show' );
};

################################################################################
get '/item/:id/unread' => sub {
################################################################################
    my $self = shift;

    my $id = $self->param('id');

    Model->do( 'UPDATE items set read = 0 WHERE id = ?', {}, $id );

    $self->redirect_to('/empty');
};

app->start();
