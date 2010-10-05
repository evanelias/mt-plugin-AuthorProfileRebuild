package AuthorProfileRebuild::App;

use strict;
use MT 4;

# Whenever an author saves their MT profile in the frontend, immediately republish
# their author archive listing.
# This can only be accomplished via monkey-patching MTCS, rather than an MT::Author
# object-level post save callback.  The reason is that MT Pro custom fields get saved
# AFTER the author object itself, so the callback occurs too early to be useful here.
sub init_app {
    my ( $cb, $app ) = @_;
    return unless $app->id eq 'community';  # Only run for the MTCS app

    # First, store a reference to the original (pre-monkeypatched) method.
    my $orig_method = \&MT::App::Community::save_profile_method;

    # Then, set the method name to point to a new closure subroutine
    *MT::App::Community::save_profile_method = sub {
        my $app       = $_[0];

        # Call the original method, passing it the original args, and store
        # its return value.
        my $returnval = $orig_method->(@_);
        # Now that the original method has completed, we can get into our new
        # code to perform additional behaviors. Voila, monkey patch.
        
        my $author    = $app->_login_user_commenter() or return $returnval;
        my $blog_id   = _blog_id_to_rebuild() or return $returnval;
        my $blog      = MT::Blog->load($blog_id) or return $returnval;

        # Only proceed if user has permissions to post.
        my $perms = MT::Permission->load({ blog_id => $blog_id,
                                           author_id => $author->id });
        # Replace the $perms->can_publish_post with a different permission
        # if you prefer!
        return $returnval unless $perms && $perms->can_publish_post;

        # Rebuild the author's archive listing
        require MT::WeblogPublisher;
        my $mt  = MT::WeblogPublisher->new();
        $mt->_rebuild_entry_archive_type(
            Blog        => $blog,
            Author      => $author,
            ArchiveType => 'Author',
            NoStatic    => 0,
            Force       => 0,
        );
        
        return $returnval;
    };
}

# utility function to return which blog_id to rebuild
sub _blog_id_to_rebuild {
    # For simplicity's sake, here we just rebuild author archives in blog_id 1.
    # In a more complete implementation, this would be a plugin config setting,
    # perhaps permitting multiple blogs to be specified.
    return 1;
}

1;
