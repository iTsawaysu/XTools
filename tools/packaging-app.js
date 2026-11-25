ObjC.import("AppKit");

const fileManager = $.NSFileManager.defaultManager;
const productName = "XTools";
const renameSwap = 0x2;
const renameExclusive = 0x4;

function bundlePath(path) {
    const url = $.NSURL.fileURLWithPath(path);
    const parent = url.URLByDeletingLastPathComponent.URLByResolvingSymlinksInPath;
    return ObjC.unwrap(parent.URLByAppendingPathComponent(url.lastPathComponent).path);
}

function fileIdentity(path) {
    const attrs = fileManager.attributesOfItemAtPathError(path, null);
    if (attrs.isNil()) return null;
    return ObjC.unwrap(attrs.objectForKey($.NSFileSystemNumber).stringValue) + ":"
        + ObjC.unwrap(attrs.objectForKey($.NSFileSystemFileNumber).stringValue);
}

function runningAt(path) {
    const apps = $.NSWorkspace.sharedWorkspace.runningApplications;
    const targetID = fileIdentity(path);
    const matching = [];
    for (let index = 0; index < Number(apps.count); index += 1) {
        const app = apps.objectAtIndex(index);
        const url = app.bundleURL;
        if (!url || url.isNil()) continue;
        if (ObjC.unwrap(url.path) === path) {
            matching.push(app);
            continue;
        }
        const executable = app.executableURL;
        const name = executable && !executable.isNil() ? ObjC.unwrap(executable.lastPathComponent) : null;
        if (name && name.toLowerCase() !== productName.toLowerCase()) continue;
        const runningPath = ObjC.unwrap(url.URLByResolvingSymlinksInPath.path);
        if (runningPath === path || (targetID && runningPath
            && runningPath.normalize().toLowerCase() === path.normalize().toLowerCase()
            && fileIdentity(runningPath) === targetID)) {
            matching.push(app);
        }
    }
    return matching;
}

function waitFor(path, running) {
    const deadline = Date.now() + 5000;
    do {
        if ((runningAt(path).length > 0) === running) return;
        $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
    } while (Date.now() < deadline);
    throw Error(running ? "Did not open the requested app at " + path : "App is still running at " + path);
}

function move(from, to) {
    if (!fileManager.moveItemAtPathToPathError(from, to, null)) {
        throw Error("Cannot move " + from + " to " + to);
    }
}

function checkDestination(target, expectedIdentity) {
    const attrs = fileManager.attributesOfItemAtPathError(target, null);
    const exists = !attrs.isNil();
    if ((fileIdentity(target) ?? "missing") !== expectedIdentity) {
        throw Error("Destination changed while packaging: " + target);
    }
    if (exists && ObjC.unwrap(attrs.objectForKey($.NSFileType)) !== ObjC.unwrap($.NSFileTypeDirectory)) {
        throw Error("Invalid app destination: " + target);
    }
    if (exists) {
        const info = $.NSDictionary.dictionaryWithContentsOfFile(target + "/Contents/Info.plist");
        if (info.isNil() || ObjC.unwrap(info.objectForKey("CFBundleExecutable")) !== productName) {
            throw Error("Not an XTools package: " + target);
        }
    }
    return exists;
}

function publish(candidate, target, expectedIdentity) {
    ObjC.bindFunction("renamex_np", ["int", ["char *", "char *", "unsigned int"]]);
    ObjC.bindFunction("__error", ["int *", []]);
    const exists = checkDestination(target, expectedIdentity);
    if ($.renamex_np(candidate, target, exists ? renameSwap : renameExclusive) === 0) return;
    const code = $.__error()[0];
    // Darwin ENOTSUP / EOPNOTSUPP. Other failures leave the old app in place.
    if (code !== 45 && code !== 102) throw Error("Cannot publish " + target + " (errno " + code + ")");

    publishByMoving(candidate, target, exists);
}

function publishByMoving(candidate, target, exists) {
    if (!exists) {
        move(candidate, target);
        return;
    }
    const previous = candidate + ".previous";
    move(target, previous);
    try {
        move(candidate, target);
    } catch (error) {
        move(previous, target);
        throw error;
    }
}

function run(argv) {
    const [action, target, candidate, mayStop, expectedIdentity] = argv;
    const path = bundlePath(target);
    if (action === "publish") checkDestination(path, expectedIdentity);
    const apps = runningAt(path);
    if (apps.length > 0) {
        if (action === "launch" && mayStop !== "yes") {
            apps[0].activateWithOptions(0);
            return;
        }
        if (mayStop !== "yes") {
            throw Error("App is running at " + path + ". Use a different OUTPUT_DIR.");
        }
        for (const app of apps) {
            if (!app.terminate && !app.terminated) {
                throw Error("Could not quit the app at " + path);
            }
        }
        waitFor(path, false);
    }
    if (action === "publish") publish(candidate, path, expectedIdentity);
    if (action === "launch") {
        const task = $.NSTask.alloc.init;
        task.executableURL = $.NSURL.fileURLWithPath("/usr/bin/open");
        task.arguments = ["-n", path];
        if (!task.launchAndReturnError(null)) throw Error("Could not run open");
        task.waitUntilExit;
        if (Number(task.terminationStatus) !== 0) throw Error("Could not open " + path);
        waitFor(path, true);
    }
}
