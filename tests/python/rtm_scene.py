"""Shared minimal RTM scene for fast tests.

The expensive part of every native RTM call is the one-time "prepare" step: building the O2
A-band line sampling table across the scene's spectral band. That cost tracks the BAND WIDTH
(number of absorption lines spanned), not the sample count, so a 701-sample and an 11-sample
full-band scene both pay ~1.0s, while a ~1.5nm window pays ~0.25-0.3s. The forward itself is
~5ms once prepared. Tests that check a contract, route parity, structure, or relative
behavior run on the narrow window; tests that pin canonical full-band physics keep the full
scene and live elsewhere.
"""


def narrow(scene=None):
    """Narrow a scene to a representative O2 A-band window (759.5-761nm, 16 samples).

    Pass an existing scene to narrow it in place (e.g. one carrying an aerosol profile), or
    omit it to build and narrow the default reference scene. The window sits on the strong
    R-branch with deep line cores, so a forward over it is a real radiative-transfer
    computation, just over a band that prepares ~4x faster than the full 755-776nm band.
    """

    if scene is None:
        from zdisamar.wavelength_bands import o2a

        scene = o2a.reference_scene()
    scene.spectral_grid.start_nm = 759.5
    scene.spectral_grid.end_nm = 761.0
    scene.spectral_grid.sample_count = 16
    return scene
