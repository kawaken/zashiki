const GhosttyI18n = @This();

const std = @import("std");
const builtin = @import("builtin");
const Config = @import("Config.zig");
const locales = @import("../os/i18n_locales.zig").locales;

const domain = "dev.kawaken.zashiki";

owner: *std.Build,
steps: []*std.Build.Step,

/// This step updates the translation files on disk that should be
/// committed to the repo.
update_step: *std.Build.Step,

pub fn init(b: *std.Build, cfg: *const Config) !GhosttyI18n {
    _ = cfg;

    var steps: std.ArrayList(*std.Build.Step) = .empty;
    defer steps.deinit(b.allocator);

    inline for (locales) |locale| {
        // There is no encoding suffix in the LC_MESSAGES path on FreeBSD,
        // so we need to remove it from `locale` to have a correct destination string.
        // (/usr/local/share/locale/en_AU/LC_MESSAGES)
        const target_locale = comptime if (builtin.target.os.tag == .freebsd)
            std.mem.trimEnd(u8, locale, ".UTF-8")
        else
            locale;

        const msgfmt = b.addSystemCommand(&.{ "msgfmt", "-o", "-" });
        msgfmt.addFileArg(b.path("po/" ++ locale ++ ".po"));

        try steps.append(b.allocator, &b.addInstallFile(
            msgfmt.captureStdOut(.{}),
            std.fmt.comptimePrint(
                "share/locale/{s}/LC_MESSAGES/{s}.mo",
                .{ target_locale, domain },
            ),
        ).step);
    }

    return .{
        .owner = b,
        .update_step = try createUpdateStep(b),
        .steps = try steps.toOwnedSlice(b.allocator),
    };
}

pub fn install(self: *const GhosttyI18n) void {
    self.addStepDependencies(self.owner.getInstallStep());
}

pub fn addStepDependencies(
    self: *const GhosttyI18n,
    other_step: *std.Build.Step,
) void {
    for (self.steps) |step| other_step.dependOn(step);
}

fn createUpdateStep(b: *std.Build) !*std.Build.Step {
    const xgettext = b.addSystemCommand(&.{
        "xgettext",
        "--language=C", // Silence the "unknown extension" errors
        "--from-code=UTF-8",
        "--keyword=_",
        "--keyword=C_:1c,2",
    });

    // Collect to intermediate .pot file
    xgettext.addArg("-o");
    const gtk_pot = xgettext.addOutputFileArg("gtk.pot");

    // Not cacheable due to the gresource files
    xgettext.has_side_effects = true;

    // NOTE: This used to also extract translatable strings from the GTK
    // apprt (blueprint UI files and src/apprt/gtk/**/*.zig), but that
    // apprt has been removed from this fork (no Linux/GTK build target).

    // Add support for localizing our `nautilus` integration
    const xgettext_py = b.addSystemCommand(&.{
        "xgettext",
        "--language=Python",
        "--from-code=UTF-8",
    });

    // Collect to intermediate .pot file
    xgettext_py.addArg("-o");
    const py_pot = xgettext_py.addOutputFileArg("py.pot");

    const nautilus_script_path = "dist/linux/ghostty_nautilus.py";
    xgettext_py.addArg(nautilus_script_path);
    xgettext_py.addFileInput(b.path(nautilus_script_path));

    // Merge pot files
    const xgettext_merge = b.addSystemCommand(&.{
        "xgettext",
        "--add-comments=Translators",
        "--package-name=" ++ domain,
        "--msgid-bugs-address=m@mitchellh.com",
        "--copyright-holder=\"Mitchell Hashimoto, Ghostty contributors\"",
        "-o",
        "-",
    });
    // py_pot needs to be first on merge order because of `xgettext` behavior around
    // charset when merging the two `.pot` files
    xgettext_merge.addFileArg(py_pot);
    xgettext_merge.addFileArg(gtk_pot);
    const usf = b.addUpdateSourceFiles();
    usf.addCopyFileToSource(
        xgettext_merge.captureStdOut(.{}),
        "po/" ++ domain ++ ".pot",
    );

    inline for (locales) |locale| {
        const msgmerge = b.addSystemCommand(&.{ "msgmerge", "--quiet", "--no-fuzzy-matching" });
        msgmerge.addFileArg(b.path("po/" ++ locale ++ ".po"));
        msgmerge.addFileArg(xgettext_merge.captureStdOut(.{}));
        usf.addCopyFileToSource(msgmerge.captureStdOut(.{}), "po/" ++ locale ++ ".po");
    }

    return &usf.step;
}
