use v6.d;
use Dev::ContainerizedService :get-spec, :docker;
use Dev::ContainerizedService::Spec;
use Test;

# Run tests in the provided body with the specified service.
sub test-service(Str $service-id, &body, Str :$tag, *%options) is export {
    # Resolve the service spec and instantiate.
    my $spec-class = get-spec($service-id);
    my Dev::ContainerizedService::Spec $spec = $spec-class.new(|%options);

    # Form the image name and try to obtain it.
    my $image = $spec.docker-container ~ ":" ~ ($tag // $spec.default-docker-tag);
    my $outcome = docker-pull-image($image);
    if $outcome ~~ Failure {
        diag $outcome.exception.message;
        skip "Could not obtain container image $image";
    }

    # Now run the container and, when ready, tests.
    my $test-error;
    react {
        my $ran-tests = False;
        my $name = "test-service-$*PID";
        my $container = Proc::Async.new: 'docker', 'run', '-t', '--rm',
                $spec.docker-options, '--name', $name, $image,
                $spec.docker-command-and-arguments;
        whenever $container.stdout.lines {
            # Discard
        }
        whenever $container.stderr.lines {
            diag "Container: $_";
        }
        whenever $container.ready {
            QUIT {
                default {
                    skip "Failed to run test service container: $_.message()";
                    done;
                }
            }
            my $ready = $spec.ready(:$name);
            whenever Promise.anyof($ready, Promise.in(60)) {
                if $ready {
                    $ran-tests = 1;
                    body($spec.service-data);
                    CATCH {
                        default {
                            $test-error = $_;
                        }
                    }
                }
                else {
                    skip "Test container did not become ready in time";
                }
                docker-stop($name);
                $container.kill;
                done;
            }
        }
        whenever $container.start {
            unless $ran-tests {
                skip "Container failed before starting tests";
                done;
            }
        }
    }
    .rethrow with $test-error;
}

=begin pod

=head1 NAME

Test::ContainerizedService - Sets up containerized services (such as databases) to ease writing integration test cases that depend on them

=head1 DESCRIPTION

This module uses containers to provide throw-away instances of services
such as databases, in order to ease testing of code that depends on them.
For example, we might wish to write a bunch of tests against a Postgres
database.  Requiring every developer who wants to run the tests to set
up a local test database is tedious and error-prone. Containers provide
a greater degree of repeatability without requiring further work on
behalf of the developer (aside from having a functioning C<docker>
installation). In the case this that C<docker> is not available or therei
are problems obtaining the container, the tests will simply be skipped.

=head1 Usage

=head2 Postgres

=begin code :lang<raku>

use Test;
use Test::ContainerizedService;
use DB::Pg;

# Either receive a formed connection string:
test-service 'postgres', -> (:$conninfo, *%) {
    my $pg = DB::Pg.new(:$conninfo);
    # And off you go...
}

# Or get the individual parts:
test-service 'postgres', -> (:$host, :$port, :$user, :$password, :$dbname, *%) {
    # Use them as you wish
}

# Can also specify the tag of the postgres container to use:
test-service 'postgres', :tag<14.4> -> (:$conninfo, *%) {
    my $pg = DB::Pg.new(:$conninfo);
}

=end code

=head2 Redis

=begin code :lang<raku>

use Test;
use Test::ContainerizedService;
use Redis;

test-service 'redis', :tag<7.0>, -> (:$host, :$port) {
    my $conn = Redis.new("$host:$port", :decode_response);
    $conn.set("eggs", "fried");
    is $conn.get("eggs"), "fried", "Hurrah, fried eggs!";
    $conn.quit;
}

=end code

=head1 The service I want isn't here!

This module is based on C<Dev::ContainerizedService>. Please follow the
instructions to add support for a service to that module; that will mean
support is provided automatically in this one also. Then:

=item 1. Fork this repository

=item 2. Add an example to the documentation

=item 3. If wanting to be extremely thorough, add a test to this repository also

=item 4. Submit a pull request

=head1 AUTHOR

Jonathan Worthington

=head1 COPYRIGHT AND LICENSE

Copyright 2022 - 2024 Jonathan Worthington

Copyright 2024 Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
