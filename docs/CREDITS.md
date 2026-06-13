# Créditos de features integradas

Este fork incorpora trabajo de otros forks de la comunidad MacDown. Cada feature
conserva la **autoría original en el histórico de git** (el autor del commit es la
persona que lo escribió; nosotros figuramos solo como *committer*). Esta tabla
documenta la procedencia de forma explícita.

El proyecto base es [`plateaukao/macdown`](https://github.com/plateaukao/macdown),
a su vez fork de [`MacDownApp/macdown`](https://github.com/MacDownApp/macdown)
(MIT, Tzu-ping Chung y colaboradores).

| Feature | Autor | Fork de origen | Commits |
|---|---|---|---|
| Font zoom + modos de vista Light/Dark/Sepia, enlaces de TOC internos, fix de crash en grupos de toolbar segmentados | **Reza Ambler** | [RezaAmbler/macdown_arm](https://github.com/RezaAmbler/macdown_arm) | `beb1bac`, `9d27a8f`, `395fba0`, `dc10f46` |
| Recarga automática del documento cuando el fichero cambia en disco | **Tim** (treehousetim) | [treehousetim/macdown](https://github.com/treehousetim/macdown) | `1b42ba3` |

> Cómo se integran: una rama `feature/*` por feature, `git cherry-pick -x`
> (preserva autor y referencia al commit original), resolución de conflictos
> documentada en el mensaje de commit, y validación de build en CI vía Pull
> Request antes de integrar a `master`.
