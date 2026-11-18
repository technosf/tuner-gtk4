# subprojects

`tuner-core` is the functional core (tuner-core repository). The GTK4 build finds it here.

While developing, make `subprojects/tuner-core` a link to a neighbouring checkout:

```bash
ln -s ../../tuner-core subprojects/tuner-core
```

To build against a tagged core instead, copy `tuner-core.wrap.example` to `tuner-core.wrap`, set the URL and the tag,
and remove the link. Meson fetches the checkout into `subprojects/tuner-core`.
