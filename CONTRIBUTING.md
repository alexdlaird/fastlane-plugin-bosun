# Contributing

If you find issues, [report them on GitHub](https://github.com/alexdlaird/fastlane-plugin-bosun/issues).

If you would like to contribute to the code, the process is pretty simple:

1. Familiarise yourself with the actions and their options in [the README](https://github.com/alexdlaird/fastlane-plugin-bosun#readme),
   and [`fastlane`'s documentation on plugins](https://docs.fastlane.tools/plugins/create-plugin/).
2. Fork [the repository on GitHub](https://github.com/alexdlaird/fastlane-plugin-bosun) and start implementing changes.
3. Write a test that plainly validates the changes made.
4. Test locally with `make test`.
5. Ensure no linting errors were introduced by running `make check`.
6. Submit a [pull request](https://help.github.com/en/articles/creating-a-pull-request-from-a-fork) to get the changes
   merged.

Moving an app onto `bosun` must not change what its lanes do, so `make test` also runs a parity suite when
`BOSUN_PARITY_DIR` is set. For each app in that folder (`<app>/<platform>/reference.Fastfile`, the app's Fastfile
before `bosun`, and `candidate.Fastfile`, the same lanes on `bosun`), every scenario runs against both, and everything
they do to the outside world must match call for call: `fastlane` actions and their arguments, App Store Connect and
Play calls, sleeps, files written, the log lines CI parses, and the result or error. The apps' Fastfiles aren't part of
this repo, so the suite is skipped without it.

Also be sure to review the [Code of Conduct](https://github.com/alexdlaird/fastlane-plugin-bosun?tab=coc-ov-file#contributor-covenant-code-of-conduct)
before submitting issues or pull requests.

Want to contribute financially? If you've found `bosun` useful, [sponsorship](https://github.com/sponsors/alexdlaird)
would also be greatly appreciated!
