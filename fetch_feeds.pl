#!/usr/bin/env perl

use strict;
use warnings;
use v5.10;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";
require Model;

Model->update_feeds;
