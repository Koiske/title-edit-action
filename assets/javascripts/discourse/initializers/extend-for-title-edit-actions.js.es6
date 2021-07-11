import { withPluginApi } from "discourse/lib/plugin-api";

function initialize(api) {

  api.addPostSmallActionIcon("title_edited", "pencil-alt");

  api.addPostTransformCallback(transformed => {
    if (transformed.actionCode === "title_edited") {
      transformed.isSmallAction = true;
      transformed.canEdit = true;
    }
  });

}

export default {
  name: "extend-for-title-edit-actions",
  initialize(container) {
    if (!Discourse.SiteSettings.discourse_title_edit_actions_enabled) {
      return;
    }

    withPluginApi("0.8.11", api => initialize(api, container));
  }
};
