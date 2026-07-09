#!/usr/bin/perl
use strict;
use warnings;
use Fcntl qw(:DEFAULT O_NONBLOCK);

our %FONT;

my $fb_path = "/dev/fb0";
my $share_log = "/mnt/share/plumos-v90s-fb-console.log";
my $share_log_copy = "/mnt/share/rootfs/plumos-v90s-fb-console.log";

my $width = read_int("/sys/class/graphics/fb0/virtual_size", 640, 0);
my $virtual_height = read_int("/sys/class/graphics/fb0/virtual_size", 480, 1);
my $stride = read_int("/sys/class/graphics/fb0/stride", $width * 4, undef);
my $bpp = read_int("/sys/class/graphics/fb0/bits_per_pixel", 32, undef);
my $visible_height = read_visible_height($virtual_height);
$visible_height = $virtual_height if $visible_height > $virtual_height;

my $scale = 2;
my $char_w = 6 * $scale;
my $char_h = 8 * $scale;
my $cols = int($width / $char_w);
my $rows = int($visible_height / $char_h);
$cols = 40 if $cols < 40;
$rows = 20 if $rows < 20;

my $fg = pack("V", 0xffffffff);
my $dim = pack("V", 0xffb0b0b0);
my $black = "\0\0\0\0";
my @page_offsets = (0);
push @page_offsets, $stride * $visible_height if $virtual_height > $visible_height;

sysopen(my $FB, $fb_path, O_RDWR) or die "open $fb_path: $!";
binmode($FB);

open(my $LOG1, ">>", $share_log);
open(my $LOG2, ">>", $share_log_copy);
select((select($LOG1), $| = 1)[0]) if $LOG1;
select((select($LOG2), $| = 1)[0]) if $LOG2;

my @screen;
my $cmd = "";
my %inputs;
my $shift = 0;
my $last_scan = 0;

push_line("plumOS V90S framebuffer console");
push_line("fb0 ${width}x${virtual_height} visible=${visible_height} stride=${stride} bpp=${bpp}");
push_line("Type commands and press Enter. Try: ls /");
run_command("uname -a");
run_command("ls /");
run_command("ls /dev/input");
redraw();

while (1) {
    my $now = time();
    if ($now != $last_scan) {
        rescan_inputs();
        $last_scan = $now;
    }

    for my $path (sort keys %inputs) {
        my $fh = $inputs{$path};
        while (1) {
            my $buf = "";
            my $n = sysread($fh, $buf, 24);
            last if !defined($n) || $n != 24;
            handle_event($buf);
        }
    }

    select(undef, undef, undef, 0.03);
}

sub read_int {
    my ($path, $fallback, $field) = @_;
    if (open(my $fh, "<", $path)) {
        my $v = <$fh>;
        close($fh);
        chomp($v) if defined $v;
        if (defined $field && defined $v && $v =~ /^(\d+),(\d+)/) {
            return $field == 0 ? $1 : $2;
        }
        return int($v) if defined $v && $v =~ /^\d+$/;
    }
    return $fallback;
}

sub read_visible_height {
    my ($fallback) = @_;
    if (open(my $fh, "<", "/sys/class/graphics/fb0/modes")) {
        my $mode = <$fh>;
        close($fh);
        if (defined $mode && $mode =~ /x(\d+)[pi-]/) {
            return int($1);
        }
    }
    return $fallback;
}

sub log_line {
    my ($line) = @_;
    print $LOG1 "$line\n" if $LOG1;
    print $LOG2 "$line\n" if $LOG2;
}

sub push_line {
    my ($line) = @_;
    $line = "" unless defined $line;
    $line =~ s/[\r\t]/ /g;
    $line =~ s/[^ -~]/?/g;
    if (length($line) == 0) {
        push @screen, "";
        log_line("");
    } else {
        while (length($line) > $cols) {
            my $chunk = substr($line, 0, $cols, "");
            push @screen, $chunk;
            log_line($chunk);
        }
        push @screen, $line;
        log_line($line);
    }
    shift @screen while @screen > ($rows - 2);
    redraw();
}

sub run_command {
    my ($line) = @_;
    $line =~ s/^\s+|\s+$//g;
    return if $line eq "";

    if ($line eq "clear") {
        @screen = ();
        redraw();
        return;
    }
    if ($line eq "help") {
        push_line("Builtins: clear help reboot poweroff");
        push_line("Commands run through /bin/sh.");
        return;
    }
    if ($line eq "reboot" || $line eq "poweroff") {
        push_line("Running $line");
        system($line);
        return;
    }

    push_line("\$ $line");
    my $count = 0;
    if (open(my $out, "-|", "/bin/sh", "-c", "$line 2>&1")) {
        while (my $out_line = <$out>) {
            chomp($out_line);
            push_line($out_line);
            $count++;
            if ($count >= 80) {
                push_line("[output truncated]");
                last;
            }
        }
        close($out);
    } else {
        push_line("exec failed: $!");
    }
}

sub rescan_inputs {
    my @paths = sort glob("/dev/input/event*");
    for my $path (@paths) {
        next if exists $inputs{$path};
        if (sysopen(my $fh, $path, O_RDONLY | O_NONBLOCK)) {
            binmode($fh);
            $inputs{$path} = $fh;
            push_line("input opened: $path");
        }
    }
}

sub handle_event {
    my ($buf) = @_;
    my ($type, $code, $value) = unpack("x16 S S l", $buf);
    return unless $type == 1;

    if ($code == 42 || $code == 54) {
        $shift = $value ? 1 : 0;
        return;
    }
    return unless $value == 1 || $value == 2;

    if ($code == 28) {
        my $line = $cmd;
        $cmd = "";
        push_line("> $line");
        run_command($line);
        redraw();
        return;
    }
    if ($code == 14) {
        chop($cmd) if length($cmd);
        redraw();
        return;
    }
    if ($code == 1) {
        $cmd = "";
        push_line("[escape]");
        return;
    }

    my $ch = key_char($code, $shift);
    if (defined $ch) {
        $cmd .= $ch;
        redraw();
    }
}

sub key_char {
    my ($code, $shifted) = @_;
    my %normal = (
        2=>"1", 3=>"2", 4=>"3", 5=>"4", 6=>"5", 7=>"6", 8=>"7", 9=>"8", 10=>"9", 11=>"0",
        12=>"-", 13=>"=", 15=>" ",
        16=>"q", 17=>"w", 18=>"e", 19=>"r", 20=>"t", 21=>"y", 22=>"u", 23=>"i", 24=>"o", 25=>"p",
        26=>"[", 27=>"]", 30=>"a", 31=>"s", 32=>"d", 33=>"f", 34=>"g", 35=>"h", 36=>"j",
        37=>"k", 38=>"l", 39=>";", 40=>"'", 41=>"`", 43=>"\\", 44=>"z", 45=>"x", 46=>"c",
        47=>"v", 48=>"b", 49=>"n", 50=>"m", 51=>",", 52=>".", 53=>"/", 57=>" ",
    );
    my %shift = (
        2=>"!", 3=>"@", 4=>"#", 5=>"\$", 6=>"%", 7=>"^", 8=>"&", 9=>"*", 10=>"(", 11=>")",
        12=>"_", 13=>"+", 16=>"Q", 17=>"W", 18=>"E", 19=>"R", 20=>"T", 21=>"Y", 22=>"U",
        23=>"I", 24=>"O", 25=>"P", 26=>"{", 27=>"}", 30=>"A", 31=>"S", 32=>"D", 33=>"F",
        34=>"G", 35=>"H", 36=>"J", 37=>"K", 38=>"L", 39=>":", 40=>"\"", 41=>"~",
        43=>"|", 44=>"Z", 45=>"X", 46=>"C", 47=>"V", 48=>"B", 49=>"N", 50=>"M",
        51=>"<", 52=>">", 53=>"?", 57=>" ",
    );
    return $shifted ? $shift{$code} : $normal{$code};
}

sub redraw {
    clear_pages();
    my $y = 0;
    draw_text(0, $y, "plumOS V90S fb console", $dim);
    $y += $char_h;
    for my $line (@screen) {
        last if $y >= ($visible_height - $char_h);
        draw_text(0, $y, $line, $fg);
        $y += $char_h;
    }
    my $prompt = "> $cmd";
    $prompt = substr($prompt, -$cols) if length($prompt) > $cols;
    draw_text(0, $visible_height - $char_h, $prompt, $fg);
}

sub clear_pages {
    my $chunk = "\0" x 4096;
    my $bytes = $stride * $visible_height;
    for my $base (@page_offsets) {
        sysseek($FB, $base, 0);
        my $left = $bytes;
        while ($left > 0) {
            my $n = $left > 4096 ? 4096 : $left;
            syswrite($FB, substr($chunk, 0, $n));
            $left -= $n;
        }
    }
}

sub draw_text {
    my ($x, $y, $text, $color) = @_;
    my $cx = $x;
    for my $ch (split //, $text) {
        last if $cx + $char_w > $width;
        draw_char($cx, $y, $ch, $color);
        $cx += $char_w;
    }
}

sub draw_char {
    my ($x, $y, $ch, $color) = @_;
    $ch = uc($ch);
    my $glyph = $FONT{$ch} || $FONT{"?"};
    for my $gy (0 .. $#$glyph) {
        my $bits = $glyph->[$gy];
        for my $sy (0 .. $scale - 1) {
            my $py = $y + ($gy * $scale) + $sy;
            next if $py < 0 || $py >= $visible_height;
            for my $gx (0 .. 4) {
                next unless substr($bits, $gx, 1) eq "1";
                my $px = $x + ($gx * $scale);
                my $run = $color x $scale;
                for my $base (@page_offsets) {
                    sysseek($FB, $base + ($py * $stride) + ($px * 4), 0);
                    syswrite($FB, $run);
                }
            }
        }
    }
}

%FONT = (
    " "=>[qw(00000 00000 00000 00000 00000 00000 00000)],
    "!"=>[qw(00100 00100 00100 00100 00100 00000 00100)],
    "\""=>[qw(01010 01010 01010 00000 00000 00000 00000)],
    "#"=>[qw(01010 01010 11111 01010 11111 01010 01010)],
    "\$"=>[qw(00100 01111 10100 01110 00101 11110 00100)],
    "%"=>[qw(11001 11010 00010 00100 01000 01011 10011)],
    "&"=>[qw(01100 10010 10100 01000 10101 10010 01101)],
    "'"=>[qw(00100 00100 01000 00000 00000 00000 00000)],
    "("=>[qw(00010 00100 01000 01000 01000 00100 00010)],
    ")"=>[qw(01000 00100 00010 00010 00010 00100 01000)],
    "*"=>[qw(00000 10101 01110 11111 01110 10101 00000)],
    "+"=>[qw(00000 00100 00100 11111 00100 00100 00000)],
    ","=>[qw(00000 00000 00000 00000 00100 00100 01000)],
    "-"=>[qw(00000 00000 00000 11111 00000 00000 00000)],
    "."=>[qw(00000 00000 00000 00000 00000 01100 01100)],
    "/"=>[qw(00001 00010 00010 00100 01000 01000 10000)],
    "0"=>[qw(01110 10001 10011 10101 11001 10001 01110)],
    "1"=>[qw(00100 01100 00100 00100 00100 00100 01110)],
    "2"=>[qw(01110 10001 00001 00010 00100 01000 11111)],
    "3"=>[qw(11110 00001 00001 01110 00001 00001 11110)],
    "4"=>[qw(00010 00110 01010 10010 11111 00010 00010)],
    "5"=>[qw(11111 10000 11110 00001 00001 10001 01110)],
    "6"=>[qw(00110 01000 10000 11110 10001 10001 01110)],
    "7"=>[qw(11111 00001 00010 00100 01000 01000 01000)],
    "8"=>[qw(01110 10001 10001 01110 10001 10001 01110)],
    "9"=>[qw(01110 10001 10001 01111 00001 00010 01100)],
    ":"=>[qw(00000 01100 01100 00000 01100 01100 00000)],
    ";"=>[qw(00000 01100 01100 00000 01100 00100 01000)],
    "<"=>[qw(00010 00100 01000 10000 01000 00100 00010)],
    "="=>[qw(00000 00000 11111 00000 11111 00000 00000)],
    ">"=>[qw(01000 00100 00010 00001 00010 00100 01000)],
    "?"=>[qw(01110 10001 00001 00010 00100 00000 00100)],
    "@"=>[qw(01110 10001 10111 10101 10111 10000 01110)],
    "A"=>[qw(01110 10001 10001 11111 10001 10001 10001)],
    "B"=>[qw(11110 10001 10001 11110 10001 10001 11110)],
    "C"=>[qw(01110 10001 10000 10000 10000 10001 01110)],
    "D"=>[qw(11110 10001 10001 10001 10001 10001 11110)],
    "E"=>[qw(11111 10000 10000 11110 10000 10000 11111)],
    "F"=>[qw(11111 10000 10000 11110 10000 10000 10000)],
    "G"=>[qw(01110 10001 10000 10111 10001 10001 01110)],
    "H"=>[qw(10001 10001 10001 11111 10001 10001 10001)],
    "I"=>[qw(01110 00100 00100 00100 00100 00100 01110)],
    "J"=>[qw(00111 00010 00010 00010 00010 10010 01100)],
    "K"=>[qw(10001 10010 10100 11000 10100 10010 10001)],
    "L"=>[qw(10000 10000 10000 10000 10000 10000 11111)],
    "M"=>[qw(10001 11011 10101 10101 10001 10001 10001)],
    "N"=>[qw(10001 11001 10101 10011 10001 10001 10001)],
    "O"=>[qw(01110 10001 10001 10001 10001 10001 01110)],
    "P"=>[qw(11110 10001 10001 11110 10000 10000 10000)],
    "Q"=>[qw(01110 10001 10001 10001 10101 10010 01101)],
    "R"=>[qw(11110 10001 10001 11110 10100 10010 10001)],
    "S"=>[qw(01111 10000 10000 01110 00001 00001 11110)],
    "T"=>[qw(11111 00100 00100 00100 00100 00100 00100)],
    "U"=>[qw(10001 10001 10001 10001 10001 10001 01110)],
    "V"=>[qw(10001 10001 10001 10001 10001 01010 00100)],
    "W"=>[qw(10001 10001 10001 10101 10101 10101 01010)],
    "X"=>[qw(10001 10001 01010 00100 01010 10001 10001)],
    "Y"=>[qw(10001 10001 01010 00100 00100 00100 00100)],
    "Z"=>[qw(11111 00001 00010 00100 01000 10000 11111)],
    "["=>[qw(01110 01000 01000 01000 01000 01000 01110)],
    "\\"=>[qw(10000 01000 01000 00100 00010 00010 00001)],
    "]"=>[qw(01110 00010 00010 00010 00010 00010 01110)],
    "^"=>[qw(00100 01010 10001 00000 00000 00000 00000)],
    "_"=>[qw(00000 00000 00000 00000 00000 00000 11111)],
    "`"=>[qw(01000 00100 00010 00000 00000 00000 00000)],
    "{"=>[qw(00010 00100 00100 01000 00100 00100 00010)],
    "|"=>[qw(00100 00100 00100 00100 00100 00100 00100)],
    "}"=>[qw(01000 00100 00100 00010 00100 00100 01000)],
    "~"=>[qw(00000 00000 01000 10101 00010 00000 00000)],
);
