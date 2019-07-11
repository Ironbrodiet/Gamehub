/*
This file is part of GameHub.
Copyright (C) 2018-2019 Anatoliy Kashkin

GameHub is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

GameHub is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GameHub.  If not, see <https://www.gnu.org/licenses/>.
*/

using Gtk;
using Gdk;
using Gee;


using GameHub.Data;
using GameHub.Data.DB;
using GameHub.Utils;
using GameHub.UI.Widgets;

namespace GameHub.UI.Dialogs
{
	public class GamePropertiesDialog: Dialog
	{
		public Game? game { get; construct; }

		private Box content;

		private Entry name_entry;
		private AutoSizeImage image_view;
		private AutoSizeImage icon_view;
		private FileChooserEntry image_entry;
		private FileChooserEntry icon_entry;

		private Box properties_box;

		public GamePropertiesDialog(Game? game)
		{
			Object(transient_for: Windows.MainWindow.instance, resizable: false, title: _("%s: Properties").printf(game.name), game: game);
		}

		construct
		{
			get_style_context().add_class("rounded");
			get_style_context().add_class(Gtk.STYLE_CLASS_FLAT);

			gravity = Gdk.Gravity.NORTH;

			content = new Box(Orientation.HORIZONTAL, 8);
			content.margin_start = content.margin_end = 6;

			properties_box = new Box(Orientation.VERTICAL, 0);

			var name_header = Styled.H4Label(_("Name"));
			name_header.xpad = 8;
			properties_box.add(name_header);

			name_entry = new Entry();
			name_entry.placeholder_text = name_entry.primary_icon_tooltip_text = _("Name");
			name_entry.primary_icon_name = "insert-text-symbolic";
			name_entry.primary_icon_activatable = false;
			name_entry.margin = 4;
			name_entry.margin_top = 0;
			properties_box.add(name_entry);

			name_entry.text = game.name;
			name_entry.changed.connect(() => {
				game.name = name_entry.text.strip();
				game.update_status();
				game.save();
				DB.Tables.IGDBData.remove(game);
			});

			var images_header = Styled.H4Label(_("Images"));
			images_header.xpad = 8;
			properties_box.add(images_header);

			var images_card = Styled.Card("gamecard", "static");
			images_card.margin = 4;

			icon_view = new AutoSizeImage();
			icon_view.margin = 4;
			icon_view.set_constraint(48, 48, 1);
			icon_view.halign = Align.START;
			icon_view.valign = Align.END;

			image_view = new AutoSizeImage();
			image_view.hexpand = false;
			image_view.set_constraint(360, 400, 0.467f);

			var actions = new Box(Orientation.VERTICAL, 0);
			actions.get_style_context().add_class("actions");
			actions.hexpand = true;
			actions.vexpand = false;

			var images_overlay = new Overlay();
			images_overlay.add(image_view);
			images_overlay.add_overlay(actions);
			images_overlay.add_overlay(icon_view);

			var images_download_btn = new MenuButton();
			images_download_btn.get_style_context().add_class("images-download-button");
			images_download_btn.margin = 8;
			images_download_btn.halign = Align.END;
			images_download_btn.valign = Align.START;
			images_download_btn.image = new Image.from_icon_name("folder-download-symbolic", IconSize.BUTTON);
			images_download_btn.tooltip_text = _("Download images");

			images_overlay.add_overlay(images_download_btn);

			images_card.add(images_overlay);
			properties_box.add(images_card);

			image_entry = add_image_entry(_("Image URL"), "image-x-generic");
			image_entry.hexpand = true;
			image_entry.margin = 4;

			var images_download_popover = new ImagesDownloadPopover(game, images_download_btn);

			properties_box.add(image_entry);

			icon_entry = add_image_entry(_("Icon URL"), "image-x-generic-symbolic");
			icon_entry.margin_top = 0;

			properties_box.add(icon_entry);

			image_view.load(game.image, "image");
			icon_view.load(game.icon, "icon");

			var space = new Box(Orientation.VERTICAL, 0);
			space.vexpand = true;
			properties_box.add(space);

			if(!(game is Data.Sources.Steam.SteamGame) && game.install_dir != null && game.install_dir.query_exists())
			{
				var executable_header = Styled.H4Label(_("Executable"));
				executable_header.xpad = 8;
				properties_box.add(executable_header);

				var executable_picker = new FileChooserEntry(_("Select executable"), FileChooserAction.OPEN, "application-x-executable", _("Executable"), false, true);
				try
				{
					executable_picker.set_default_directory(game.install_dir);
					executable_picker.select_file(game.executable);
				}
				catch(Error e)
				{
					warning(e.message);
				}
				executable_picker.margin_start = executable_picker.margin_end = 4;
				properties_box.add(executable_picker);

				executable_picker.file_set.connect(() => {
					game.set_chosen_executable(executable_picker.file);
				});

				var args_entry = new Entry();
				args_entry.text = game.arguments ?? "";
				args_entry.placeholder_text = args_entry.primary_icon_tooltip_text = _("Arguments");
				args_entry.primary_icon_name = "utilities-terminal-symbolic";
				args_entry.primary_icon_activatable = false;
				args_entry.margin = 4;

				args_entry.changed.connect(() => {
					game.arguments = args_entry.text.strip();
					game.update_status();
					game.save();
				});

				properties_box.add(args_entry);

				var compat_header = Styled.H4Label(_("Compatibility"));
				compat_header.no_show_all = true;
				compat_header.xpad = 8;
				properties_box.add(compat_header);

				var compat_force_switch = add_switch(_("Force compatibility mode"), game.force_compat, f => { game.force_compat = f; });
				compat_force_switch.no_show_all = true;

				var compat_tool = new CompatToolPicker(game, false, true);
				compat_tool.no_show_all = true;
				compat_tool.margin_start = compat_tool.margin_end = 4;
				properties_box.add(compat_tool);

				game.notify["use-compat"].connect(() => {
					compat_force_switch.visible = !game.needs_compat;
					compat_tool.visible = game.use_compat;
					compat_header.visible = compat_force_switch.visible || compat_tool.visible;
					game.update_status();
				});
				game.notify_property("use-compat");
			}

			var gh_run_args_header = Styled.H4Label(_("Launch from terminal"));
			gh_run_args_header.xpad = 8;
			properties_box.add(gh_run_args_header);

			var gh_run_args_box = new Box(Orientation.HORIZONTAL, 0);
			gh_run_args_box.get_style_context().add_class(Gtk.STYLE_CLASS_LINKED);
			gh_run_args_box.margin_start = gh_run_args_box.margin_end = gh_run_args_box.margin_bottom = 4;

			var gh_run_args_entry = new Entry();
			gh_run_args_entry.hexpand = true;
			gh_run_args_entry.text = ProjectConfig.PROJECT_NAME + " --run " + game.full_id;
			gh_run_args_entry.editable = false;
			gh_run_args_entry.primary_icon_name = "utilities-terminal-symbolic";
			gh_run_args_entry.primary_icon_activatable = false;
			gh_run_args_entry.secondary_icon_name = "edit-copy-symbolic";
			gh_run_args_entry.secondary_icon_activatable = true;
			gh_run_args_entry.secondary_icon_tooltip_text = _("Copy to clipboard");

			var gh_add_to_steam_btn = new Button.with_label(_("Add to Steam"));
			gh_add_to_steam_btn.tooltip_text = _("Add to the Steam library");

			gh_add_to_steam_btn.clicked.connect(() => {
				Data.Sources.Steam.Steam.add_game_shortcut(game);
			});

			gh_run_args_box.add(gh_run_args_entry);
			gh_run_args_box.add(gh_add_to_steam_btn);

			properties_box.add(gh_run_args_box);

			gh_run_args_entry.icon_press.connect((icon, event) => {
				if(icon == EntryIconPosition.SECONDARY && ((EventButton) event).button == 1)
				{
					gh_run_args_entry.select_region(0, -1);
					gh_run_args_entry.copy_clipboard();
				}
			});

			content.add(new GameTagsList(game));
			content.add(new Separator(Orientation.VERTICAL));
			content.add(properties_box);

			get_content_area().add(content);
			get_content_area().set_size_request(640, 480);

			delete_event.connect(() => {
				image_entry.activate();
				icon_entry.activate();
				set_image_url(true);
				set_icon_url(true);
				game.save();
				destroy();
			});

			show_all();
		}

		private void set_image_url(bool replace=false)
		{
			var url = image_entry.uri;
			if(url == null || url.length == 0) url = game.image;
			if(replace)
			{
				game.image = url;
			}
			else
			{
				image_view.load(url, "image");
			}
		}

		private void set_icon_url(bool replace=false)
		{
			var url = icon_entry.uri;
			if(url == null || url.length == 0) url = game.icon;
			if(replace)
			{
				game.icon = url;
			}
			else
			{
				icon_view.load(url, "icon");
			}
		}

		private FileChooserEntry add_image_entry(string text, string icon)
		{
			var entry = new FileChooserEntry(text, FileChooserAction.OPEN, icon, text, true);
			entry.margin = 4;

			var filter = new FileFilter();
			filter.add_mime_type("image/*");
			entry.chooser.set_filter(filter);

			entry.uri_set.connect(() => { set_image_url(false); set_icon_url(false); });

			return entry;
		}

		private Box add_switch(string text, bool enabled, owned SwitchAction action)
		{
			var sw = new Switch();
			sw.active = enabled;
			sw.halign = Align.END;
			sw.notify["active"].connect(() => { action(sw.active); });

			var label = new Label(text);
			label.halign = Align.START;
			label.hexpand = true;

			var hbox = new Box(Orientation.HORIZONTAL, 12);
			hbox.margin = 4;
			hbox.margin_start = 8;

			hbox.add(label);
			hbox.add(sw);

			hbox.show_all();

			properties_box.add(hbox);
			return hbox;
		}

		protected delegate void SwitchAction(bool active);
	}
}
