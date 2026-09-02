import { Config } from "@remotion/cli/config";

Config.setVideoImageFormat("jpeg");
Config.setOverwriteOutput(true);
// Two browser tabs at 2560 by 1440 fit comfortably on this machine. Raise it
// with `npm run render -- --concurrency=4` if there is memory to spare.
Config.setConcurrency(2);
