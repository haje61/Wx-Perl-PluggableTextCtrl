package Wx::Perl::PluggableTextCtrl::Highlighter;

use strict;
use warnings;
use Carp;

use Wx qw( :textctrl :font :colour :timer );
use base qw( Wx::Perl::PluggableTextCtrl::BasePlugin );
use Wx::Event qw( EVT_TIMER );

my $debug = 0;

if ($debug) {
   use Data::Dumper;
}

my $defaultfont = [10, wxFONTFAMILY_MODERN, wxFONTSTYLE_NORMAL, wxFONTWEIGHT_NORMAL, 0];

my $blue                = [0x00, 0x00, 0xff];
my $lightblue           = [0xad, 0xd8, 0xe6];
my $darkblue            = [0x00, 0x00, 0x80];
my $green               = [0x00, 0xff, 0x00];
my $lightgreen          = [0x90, 0xee, 0x90];
my $darkgreen           = [0x00, 0x80, 0x00];
my $brown               = [0xa5, 0x2a, 0x2a];
my $red                 = [0xff, 0x00, 0x00];
my $orange              = [0xff, 0xa5, 0x00];
my $purple              = [0x80, 0x00, 0x80];
my $cyan                = [0x00, 0xff, 0xff];
my $magenta             = [0xff, 0x00, 0xff];
my $yellow              = [0xff, 0xff, 0x00];
my $beige               = [0xf5, 0xf5, 0xdc];
my $black               = [0x00, 0x00, 0x00];
my $white               = [0xff, 0xff, 0xfe];

my $defaultstyles = [
   ['Alert', $orange, $blue],
   ['BaseN', $darkgreen],
   ['BString', $purple],
   ['Char', $magenta],
   ['Comment', undef, undef, [undef, undef, wxFONTSTYLE_ITALIC]],
   ['DataType', $blue],
   ['DecVal', $darkblue, undef, [undef, undef, undef, wxFONTWEIGHT_BOLD]],
   ['Error',  $red, $yellow],
   ['Float', $darkblue, undef, [undef, undef, undef, wxFONTWEIGHT_BOLD]],
   ['Function', $brown],
   ['IString', $red],
   ['Keyword', $black, undef, [undef, undef, undef, wxFONTWEIGHT_BOLD]],
   ['Normal', ],
   ['Operator', $orange],
   ['Others', $orange, $beige],
   ['RegionMarker', $lightblue],
   ['Reserved', $purple, $beige],
   ['String', $red],
   ['Variable', $blue, $lightgreen],
];

sub new {
   my $class = shift;
   my $self = $class->SUPER::new(@_);

   $self->{BASICSTATE} = undef;
   $self->{BLOCKSIZE} = 128;
   $self->{ENABLED} = 0;
   $self->{ENGINE} = undef;
   $self->{HLEND} = 0;
   $self->{INTERVAL} = 1;
   $self->{LINEINFO} = [];
   $self->{STYLES} = {};
   $self->{TIMER} = Wx::Timer->new($self->TxtCtrl);
   
   $self->SetStyles($defaultstyles);
   $self->Commands(
      'clear' => \&Clear,
      'load' => \&Load,
      'syntax' => \&Syntax,

      'doremove' => \&Purge,
      'doreplace' => \&Purge,
      'dowrite' => \&Purge,
      'remove' => \&Purge,
      'replace' => \&Purge,
      'write' => \&Purge,
   );
   $self->EngineInit;
   $self->Require('KeyEchoes');

   EVT_TIMER($self->TxtCtrl, -1, sub { $self->Loop });

   return $self;
}

sub BasicState {
   my $self = shift;
   if (@_) { $self->{BASICSTATE} = shift; }
   return $self->{BASICSTATE};
}

sub BlockSize {
   my $self = shift;
   if (@_) { $self->{BLOCKSIZE} = shift; }
   return $self->{BLOCKSIZE};
}

sub Active {
   my $self = shift;
   if (@_) { $self->{ACTIVE} = shift; }
   return $self->{ACTIVE};
}

sub Clear {
   my $self = shift;
   my $tc = $self->TxtCtrl;
   $tc->SetStyle(0, $tc->GetLastPosition, $self->Styles->{'Normal'});
   $self->Engine->reset;
   $self->{LINEINFO} = [];
   $self->HlEnd(0);
   return 0
}

sub Enabled {
   my $self = shift;
   if (@_) {
      my $state = shift;
      $self->{ENABLED} = $state;
      unless ($state) { $self->Clear; }
   }
   return $self->{ENABLED};
}

sub Engine {
   my $self = shift;
   if (@_) { $self->{ENGINE} = shift; }
   return $self->{ENGINE};
}

#1st world problem: I definitely need a faster higlighter;
sub EngineInit {
   my $self = shift;
   unless (defined($self->Engine)) {
      require Syntax::Highlight::Engine::Kate;
      $self->Engine(new Syntax::Highlight::Engine::Kate);
   }
}

sub HlEnd {
   my $self = shift;
   if (@_) { $self->{HLEND} = shift; }
   return $self->{HLEND};
}

sub Interval {
   my $self = shift;
   if (@_) { $self->{INTERVAL} = shift; }
   return $self->{INTERVAL};
}

sub HighlightLine {
   my ($self, $num) = @_;
   my $tc = $self->TxtCtrl;
   my $hlt = $self->Engine;
   my $begin = $tc->XYToPosition(0, $num); 
   my $end = $begin + $tc->GetLineLength($num) + 1;
   my $li = $self->{LINEINFO};
   my $k;
   if ($num eq 0) {
      $k = $self->BasicState;
   } else {
      $k = $li->[$num - 1];
   }
   $hlt->stateSet(@$k);
   $tc->SetStyle($begin, $end, $self->Styles->{'Normal'});
   my $txt = $tc->GetRange($begin, $end); #get the text to be highlighted
   if ($txt ne '') { #if the line is not empty
      my $pos = 0;
      my $start = 0;
      my @h = $hlt->highlight($txt);
      while (@h ne 0) {
         $start = $pos;
         $pos += length(shift @h);
         my $tag = shift @h;
         $tc->SetStyle($begin + $start, $begin + $pos, $self->Styles->{$tag});
      };
   };
   $li->[$num] = [ $hlt->stateGet ];
}

sub InitLoop {
   my $self = shift;
   unless ($self->Active) {
      $self->{TIMER}->Start($self->Interval, 1);
   };
}

sub Load { # TODO
   my ($self, $file) = @_;
   $self->Clear;
   $self->Syntax($self->Engine->languagePropose($file));
   return 0
}

sub Loop {
   my $self = shift;
   if ($self->Enabled) {
      my $hlend = $self->HlEnd;
      if ($hlend < $self->TxtCtrl->GetNumberOfLines) {
         $self->Active(0);
         $self->HighlightLine($hlend);
         $hlend ++;
         $self->HlEnd($hlend);
         $self->InitLoop;
      } else {
         $self->Active(0);
         if ($debug) {
            my $i = $self->{LINEINFO};
            my $size = @$i;
            print "hilight stack size $size\n";
         }
      }
   }
}

sub Purge {
   my ($self, $index) = @_;
   my $line = $self->TxtCtrl->GetLineNumber($index);
   if ($line <= $self->HlEnd) {
      $self->HlEnd($line);
      my $cli = $self->{LINEINFO};
      if (@$cli) { splice(@$cli, $line) };
      $self->InitLoop;
   }
   return 0;
}

sub SetStyles {
   my ($self, $styles) = @_;
   my $tc = $self->TxtCtrl;
   $self->Styles({});
   foreach (@$styles) {
      my @s = @$_;
      my $name = shift @s;
      my $fgcolour = shift @s;
      my $bgcolour = shift @s;
      my $fontinfo = shift @s;
      my ($fg, $bg, $font) = (undef, undef, undef);
      my $attr = Wx::TextAttr->new;
      if (defined($fgcolour)) {
         $attr->SetTextColour(Wx::Colour->new(@$fgcolour));
      } else {
         $attr->SetTextColour($tc->GetForegroundColour);
      }
      if (defined($bgcolour)) {
         $attr->SetBackgroundColour(Wx::Colour->new(@$bgcolour));
      } else {
         $attr->SetBackgroundColour($tc->GetBackgroundColour);
      }
      if (defined($fontinfo)) {
         my $curfont = $tc->GetFont;

         my $size = shift @$fontinfo;
         unless (defined($size)) { $size = $curfont->GetPointSize }

         my $family = shift @$fontinfo;
         unless (defined($family)) { $family = $curfont->GetFamily }

         my $style = shift @$fontinfo;
         unless (defined($style)) { $style = $curfont->GetStyle }

         my $weight = shift @$fontinfo;
         unless (defined($weight)) { $weight = $curfont->GetWeight }

         my $underline = shift @$fontinfo;
         unless (defined($underline)) { $underline = $curfont->GetUnderlined }

         my $face = shift @$fontinfo;
         unless (defined($face)) { $face = $curfont->GetFaceName }

         $font = Wx::Font->new($size, $family, $style, $weight, $underline, $face);
         $attr->SetFont($font);
      }  else {
         $attr->SetFont($tc->GetFont);
      }

      $self->Styles->{$name} = $attr;
   }
}

sub Styles {
   my $self = shift;
   if (@_) { $self->{STYLES} = shift; }
   return $self->{STYLES};
}

sub Syntax {
   my ($self, $syntax) = @_;
   if ($syntax eq 'Off') {
      $self->Clear;
   } else {
      $self->Enabled(1);
      my $e = $self->Engine;
      $e->language($syntax);
      $self->HlEnd(0);
      $self->{LINEINFO} = [];
      $self->BasicState([ $e->stateGet]);
      $self->InitLoop;
   }
   return 1
}


1;
__END__
