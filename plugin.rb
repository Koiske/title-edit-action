# name: discourse-title-edit-actions
# version: 1.0.0
# authors: buildthomas

enabled_site_setting :discourse_title_edit_actions_enabled

register_svg_icon "pencil-alt" if respond_to?(:register_svg_icon)

register_asset "stylesheets/common/title-edit-actions.scss"

after_initialize do

    class TitleEditActionHandler

        def initialize(editor, topic, old_title, new_title)
            @editor = editor
            @topic = topic
            @old_title = old_title
            @new_title = new_title
        end

        def self.diff_size(before, after)
            begin
                ONPDiff.new(before, after).short_diff.sum do |str, type|
                    type == :common ? 0 : str.size
                end
            end
        end

        def diff_text
            prev = "<div>#{CGI::escapeHTML(@old_title)}</div>"
            cur = "<div>#{CGI::escapeHTML(@new_title)}</div>"

            DiscourseDiff.new(prev, cur).inline_html
        end

        def add_action
            @topic.add_moderator_post(
                @editor,
                diff_text,
                bump: SiteSetting.discourse_title_edit_actions_bump,
                post_type: Post.types[:small_action],
                action_code: "title_edited",
                custom_fields: {
                    "old" => @old_title,
                    "new" => @new_title
                }
            )
        end

        def update_action(action)
            # Diff from the older version of the title to newest
            @old_title = action.custom_fields["old"]

            action.revise(
                action.user,
                raw: diff_text,
                bump: SiteSetting.discourse_title_edit_actions_bump,
                custom_fields: {
                    "old" => @old_title,
                    "new" => @new_title
                }
            )
        end

        def silent_edit?
            return @editor == @topic.user || # User edited their own topic
                @old_title == @new_title || # Title didn't change

                @editor.trust_level > SiteSetting.discourse_title_edit_actions_max_tl || # Exception by trust level
                (@editor.moderator? && !SiteSetting.discourse_title_edit_actions_include_mods) || # Exception for moderator
                (@editor.admin? && !SiteSetting.discourse_title_edit_actions_include_admins) || # Exception for admin

                ((@topic.user.staff? || @topic.user == Discourse.system_user) && # Exception for topics made by staff
                    SiteSetting.discourse_title_edit_actions_exclude_staff_posts) ||

                TitleEditActionHandler.diff_size(@old_title, @new_title) < # Must be a significant title edit
                    SiteSetting.discourse_title_edit_actions_min_diff_length
        end

        def handle
            # Find last post in topic
            post = @topic.ordered_posts.where.not(post_type: Post.types[:whisper]).last

            if post.post_type == Post.types[:small_action] && post.action_code == "title_edited" && (post.user == @editor || silent_edit?)
                # Last post on the topic is title edit action by same user, so update that notice instead
                update_action(post)
            else
                # Add new title edit action on the topic indicating the current edit
                add_action unless silent_edit?
            end
        end
    end

    module PostRevisorInterceptor
        def revise!(editor, fields, opts = {})
            handler = nil

            # Save reference to old/new title before edit
            if SiteSetting.discourse_title_edit_actions_enabled && @post.is_first_post?
                new_title = fields.with_indifferent_access[:title]
                if new_title
                    handler = TitleEditActionHandler.new(editor, @post.topic, @post.topic.title, new_title)
                end
            end

            # Perform edit
            success = super(editor, fields, opts)

            # Handle any title edit actions that need to be created/updated
            if SiteSetting.discourse_title_edit_actions_enabled && success && handler
                handler.handle
            end

            # Return original success value from performing edit
            success
        end
    end

    PostRevisor.send(:prepend, PostRevisorInterceptor)

end
