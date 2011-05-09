package HTML::Walk;

use strict;
use warnings;

use Data::Dumper;
use HTML::TreeBuilder;
use HTTP::Request;
use LWP::UserAgent;

use base qw(Class::Accessor::Fast);

__PACKAGE__->mk_accessors(qw(url log_processed method user passwd));

sub new {
    my ($self, %args) = @_;
    my $attr = {
        version => 0.01,
    };

    foreach my $args_key (keys %args) {
        $attr->{$args_key} = $args{$args_key};
    }

    if (!defined $attr->{method} || $attr->{method} eq '') {
        $attr->{method} = 'GET';
    }

    bless $attr, $self;
}

sub walk {
    my ($self, %args) = @_;

    if (!defined $self->log_processed) {
        print 'error: set processed log path.' . "\n";
        exit;
    }

    if (!defined $self->url && !defined $args{url}) {
        print 'error: no target url.' . "\n";
    }
    my $url = defined $args{url} && $args{url} ne '' ? $args{url} : $self->url;

    my $process_subref = defined $args{process_subref} ? $args{process_subref} : '';

    my $method = uc $self->method;

    my $ua = LWP::UserAgent->new();
    my $req = HTTP::Request->new('HEAD', $url);

    # basic auth.
    if (defined $self->user && $self->user ne '' && defined $self->passwd && $self->passwd ne '') {
        $req->authorization_basic($self->user, $self->passwd);
    }

    if (defined $args{args}) {
        $req->content($args{args});
    }

    my $res = $ua->request($req);

    if ($res->{_headers}->{'content-type'} !~ /^(text\/html|application\/xhtml)/) {
        # logging.
        if (open my $file, '>>' . $self->log_processed) {
            print $file '- ' . $res->{_headers}->{'content-type'} . "\n";
            close $file;
        }
        return 0;
    }
    # logging.
    if (open my $file, '>>' . $self->log_processed) {
        print $file $res->{_headers}->{'content-type'} . "\n";
        close $file;
    }

    $req->{_method} = $method;
    $res = $ua->request($req);

    my $content = $res->decoded_content;

    my $builder = HTML::TreeBuilder->new_from_content($content);
    my @list = $builder->find(_tag => 'a');

    foreach my $each (@list) {
        my $url_each = '';
        if (defined $each->{href} && $each->{href} ne '') {
            $url_each = $each->{href};
        }
        else {
            next;
        }

        if ($url_each !~ /^http/) {
            my $url_base = $self->url;
            $url_base =~ s/\/$//;
            $url_each = $url_base . $url_each;
        }

        my @list_processed = ();
        if (open my $file, $self->log_processed) {
            @list_processed = <$file>;
            close $file;
        }

        if (!grep(/\Q${url_each}/, @list_processed)) {
            if (ref $process_subref eq 'CODE') {
                $process_subref->(url_each => $url_each);
            }

            # logging.
            if (open my $file, '>>' . $self->log_processed) {
                print $file $url_each . "\n";
                close $file;
            }
            else {
                print 'error: can\'t open processed log.' . "\n";
                exit;
            }

            $self->walk(url => $url_each, process_subref => $process_subref);
        }
    }
}

1;

__END__

=head1 NAME

HTML::Walk - walk and find links and process these on html.

=head1 SYNOPSIS

    use HTML::Walk;

    my $html_walk = HTML::Walk->new(
        url => 'http://google.com/', 
        log_processed => './log_processed', 
        method => 'get', 
        args => 'foo=a&bar=b', 
        user = 'uid_basic_auth', 
        passwd => 'passwd_basic_auth'
    );

    $html_walk->walk(
        process_subref => 
            sub {
                my (%args) = @_; print $args{'url_each'};
            },
    );

=head1 AUTHOR

    Qinuau
