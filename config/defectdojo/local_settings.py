# -*- coding: utf-8 -*-
# Override de settings para el LAB: servir los archivos estáticos (CSS/JS) con
# WhiteNoise directamente desde uwsgi, sin necesitar el contenedor nginx.
#
# Sin esto, DefectDojo delega /static/ a nginx; como aquí no lo tenemos, el UI
# salía "en blanco" (los /static/*.css devolvían 404). WhiteNoise (ya incluido
# en la imagen) los sirve desde los finders del código (no requiere collectstatic).
#
# Este archivo lo copia el entrypoint desde /app/docker/extra_settings/ y lo
# importa DefectDojo al final de sus settings, así que aquí MIDDLEWARE ya existe.
try:
    _wn = "whitenoise.middleware.WhiteNoiseMiddleware"
    _mw = list(MIDDLEWARE)  # noqa: F821 (MIDDLEWARE viene de settings.dist)
    if _wn not in _mw:
        # Insertar justo después de SecurityMiddleware (posición recomendada).
        _i = next((i for i, m in enumerate(_mw) if "SecurityMiddleware" in m), 0)
        _mw.insert(_i + 1, _wn)
        MIDDLEWARE = _mw
    # Servir desde los finders (dirs de estáticos del código), sin collectstatic.
    WHITENOISE_USE_FINDERS = True
    WHITENOISE_AUTOREFRESH = True
except Exception:
    # Si algo falla, no romper el arranque de DefectDojo.
    pass
