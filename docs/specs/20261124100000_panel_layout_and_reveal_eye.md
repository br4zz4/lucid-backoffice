---
title: Nova estrutura visual do painel — sidebar com contexto e revelação por um olho único
status: proposed
created: 2026-11-24
updated: 2026-11-24
owner: "@oporpino"
certainty: high
---

# Nova estrutura visual do painel — sidebar com contexto e revelação por um olho único

> **TLDR**: trocar a nav do topo por uma sidebar com o **contexto** atual (compartilhado ou um tenant), uma topbar com o **olho** de revelação ao lado do Sair (um clique, um motivo num modal, revela todas as categorias permitidas no contexto) e páginas com cabeçalho padrão (breadcrumb, título, ações à direita, estado vazio). Remove a lista "Revelar dados" por categoria e corrige o contraste e o estado indisponível das Ações. Vale para painéis com e sem tenancy. Entrega a gem 0.3.0 e ajusta o luneta.

Spec 1 de 2 (a seguinte é `20261124100100_record_management.md`). Protótipo aprovado: `docs/prototypes/PROTOTYPE_panel_layout.html` (sidebar e card de contexto da variante C, topbar e registro em página própria da variante A). Glossário: `docs/CONTEXT.md`.

# what

Como operador do painel, quero ver em que contexto estou, navegar pelas tabelas numa sidebar e revelar os dados de uma vez por um olho ao lado do Sair, para operar sem uma parede de formulários por categoria e sem me perder entre tenants.

## out of scope

- Busca, filtros, ordenação, links de chave estrangeira, card "Relacionados", criar/editar/excluir registros e campos travados: Spec B (`20261124100100_record_management.md`).
- Menus de plugin dentro do contexto de tenant (`r.menu(..., scope: :tenant)`): fica para issue; menus de plugin aparecem só no contexto compartilhado.
- Tema claro, novos tokens de tema, i18n de novos idiomas.
- Revelar categorias selecionadas (um checkbox por categoria): o olho revela tudo o que o operador pode revelar.
- Encerrar a revelação automaticamente ao trocar de contexto.
- Feature flag: não há (ver `# how`).

## acceptance criteria

    Cenário: sidebar mostra o contexto compartilhado por padrão
      Dado um painel com config.tenancy = :lucid_tenancy e os tenants "alfa" e "beta"
      E um operador com as permissões view_dashboard, view_tenant, browse, view_activity e reveal
      Quando ele abre "/backoffice"
      Então a sidebar mostra o card de contexto "Compartilhado" com o nome do schema compartilhado
      E a seção "Dados" lista as tabelas do schema compartilhado
      E os itens de menu de plugin aparecem na sidebar
      E a topbar mostra o olho e o Sair, nessa ordem, à direita

    Cenário: entrar no contexto de um tenant
      Dado o mesmo painel
      Quando o operador escolhe "alfa" no card de contexto
      Então ele vai para "/backoffice/tenants/alfa"
      E o card mostra "alfa" com as opções "Trocar" e "Sair do tenant"
      E a seção "Dados" lista as tabelas do schema de "alfa"
      E a sidebar mostra "Visão do tenant" e "Atividade" apontando para "/backoffice/tenants/alfa/activity"
      E os itens de menu de plugin não aparecem

    Cenário: sair do tenant volta ao compartilhado
      Dado o operador no contexto "alfa"
      Quando ele clica em "Sair do tenant"
      Então ele vai para "/backoffice" e o card mostra "Compartilhado"

    Cenário: painel sem tenancy
      Dado um painel com config.tenancy = :none
      Quando o operador abre qualquer página
      Então o card de contexto mostra "Compartilhado" sem "Trocar" nem "Sair do tenant"
      E nenhum texto da página contém a palavra "tenant"
      E a seção "Dados" lista as tabelas do schema atual

    Cenário: revelar tudo com um motivo
      Dado o operador no contexto "alfa" sem revelação ativa
      Quando ele clica no olho
      Então abre um modal "Revelar dados de alfa" com um campo de motivo e o botão "Revelar" desabilitado
      Quando ele digita um motivo com pelo menos reveal_reason_min caracteres e confirma
      Então existe um Reveal ativo para cada categoria configurada diferente de "public" que ele pode revelar em "alfa"
      E um evento "backoffice.reveal.grant" por categoria, todos com o mesmo motivo
      E o olho aparece ativo com "Revelado até HH:MM"

    Cenário alternativo: motivo curto não revela nada
      Dado o modal aberto
      Quando o operador envia um motivo com menos de reveal_reason_min caracteres
      Então nenhum Reveal é criado, nenhum evento é gravado e a página mostra o erro

    Cenário alternativo: categoria negada é pulada
      Dado que authorize nega :reveal para a categoria "minors" e permite as demais
      Quando o operador revela com um motivo válido
      Então existe Reveal para todas as categorias permitidas e nenhum para "minors"

    Cenário alternativo: nenhuma categoria permitida
      Dado que authorize nega :reveal para todas as categorias
      Quando o operador envia POST /backoffice/reveals
      Então a resposta é 403 e nenhum Reveal é criado

    Cenário: encerrar tudo pelo olho
      Dado o operador com Reveals ativos em "alfa"
      Quando ele clica no olho ativo
      Então todos os Reveals ativos dele em "alfa" ficam revogados
      E um evento "backoffice.reveal.revoke" por categoria é gravado
      E o olho volta ao estado mascarado

    Cenário: revelação vale só para o contexto
      Dado o operador com Reveals ativos em "alfa"
      Quando ele entra em "beta"
      Então o olho aparece mascarado e os dados de "beta" continuam mascarados
      Quando ele volta para "alfa"
      Então o olho aparece ativo com o mesmo prazo

    Cenário alternativo: sem permissão de revelar
      Dado um operador sem a permissão reveal
      Quando ele abre qualquer página
      Então o olho não aparece

    Cenário: lista "Revelar dados" por categoria não existe mais
      Quando o operador abre "/backoffice/data/users", "/backoffice/data" ou "/backoffice/tenants/alfa"
      Então nenhuma página tem formulário com a classe "lb-reason-form" nem a seção "lb-reveal"
      E a rota "DELETE /backoffice/reveals/:id" não existe

    Cenário: cabeçalho padrão de página
      Quando o operador abre "/backoffice/tenants/alfa/data/users/42"
      Então a página mostra o breadcrumb "Compartilhado / alfa / Dados / users / #42"
      E o título "users #42"
      E as Ações do registro à direita do título

    Cenário: Ações legíveis e indisponíveis de verdade
      Dado uma Ação disponível e uma Ação com unavailable "Sem migrations pendentes"
      Quando o operador abre a página do tenant
      Então a Ação disponível é um botão com o texto visível (cor do texto diferente da cor de fundo)
      E a indisponível é um botão desabilitado (aria-disabled="true", tracejado, sem link) com o motivo logo abaixo dele

    Cenário: mais de 3 Ações viram menu
      Dado um registro com 4 Ações visíveis
      Quando o operador abre o registro
      Então a primeira Ação aparece como botão e as outras 3 dentro de um menu "Ações"

    Cenário: estado vazio
      Dado a tabela "users" sem linhas
      Quando o operador abre "/backoffice/tenants/alfa/data/users"
      Então a página mostra "Nenhum registro em users" em vez de uma tabela só com cabeçalho

    Cenário: mobile
      Dado uma janela com largura menor que 40rem
      Quando o operador abre qualquer página
      Então a sidebar fica recolhida atrás de um botão "Menu" na topbar
      E o olho e o Sair continuam visíveis na topbar

    Cenário: luneta usa a nova versão
      Dado o luneta com lucid-backoffice v0.3.0
      Quando um superadmin abre "/backoffice"
      Então a sidebar lista "organizations", "subdomain_provisionings" e "sysadmins" em "Dados"
      E não há itens de menu duplicados "Escolas", "Provisionamentos" e "Sysadmins"
      E os testes de revelação do luneta passam com POST /backoffice/reveals sem category

# why

A tela atual empilha 6 formulários "Motivo + Revelar" no rodapé de cada página. É difícil de ler, obriga o operador a pensar em categorias e repete o mesmo motivo até 6 vezes. A nav do topo não mostra em que tenant o operador está, e não há como navegar pelas tabelas sem voltar à lista. As Ações têm um bug visual: `.lb a { color: var(--lb-accent) }` vence `.lb-button`, e o texto some no fundo de destaque. A indisponível parece ativa porque o CSS só estiliza `:disabled`, e o motivo fica solto entre os botões. A Spec B (gerenciar dados) precisa de uma estrutura com sidebar, cabeçalho e lugar para ações antes de ganhar busca, filtros e formulários.

# how

Repos:
- **gem**: `~/workspace/br4zz4/lucid-backoffice` (`br4zz4/lucid-backoffice`). Suíte: `bundle exec rake test`.
- **luneta**: `~/workspace/brazza.tech/lunetamagica`, app em `modules/core/code`. Suíte: `make core.test`.

Decisões de implementação:
- **Feature flag:** não há. É troca de apresentação numa gem pré-1.0 com um único consumidor (luneta), migrado no último PR. Uma flag manteria dois layouts vivos sem ganho. A quebra vai no `CHANGELOG` como breaking.
- **Contexto** (glossário): um helper `current_context` devolve `Lucid::Backoffice::Context::Current` (`Data.define(:tenant, :label, :identifier, :shared)`), montado só pela interface do adaptador (`multi_tenant?`, `tenants`, `find`, `identifier`, `label`, `shared_schema`). Nunca chama `Lucid::Tenancy`. O rótulo do compartilhado é `configuration.terms.fetch(:shared, t("lucid_backoffice.shared"))`, com o nome do schema (`tenancy.shared_schema`) em mono embaixo. "Trocar" e "Sair do tenant" só aparecem com `tenancy.multi_tenant?`. A palavra do tenant usa `configuration.terms.fetch(:tenant, t("lucid_backoffice.tenant"))`.
- **Troca de contexto:** é navegação, sem estado em sessão. Compartilhado = rotas sem `tenants/:tenant_id`; tenant = rotas com o prefixo. "Trocar" é um `<details>` com a lista de `tenancy.tenants` (filtrada por `allowed?(:view_tenant, tenant:)`), cada item linkando para `tenant_path`.
- **Olho:** `POST /reveals` sem `category` chama `Reveal.grant_all`. `DELETE /reveals` (rota de coleção) chama `Reveal.revoke_all`. O modal é um `<dialog>` aberto por `data-lb-reveal-open` no JS existente; sem JS, o botão do olho é um `<details>` que mostra o mesmo formulário inline (degradação). O formulário reaproveita `data-lb-reason-form` (botão desabilitado até o mínimo).
- **Mobile:** a sidebar fica dentro de `<details class="lb-sidebar-toggle">` abaixo de 40rem, com o `summary` "Menu" na topbar. Só CSS e HTML nativo.
- **Telas criadas ou editadas** (para o ping, mas `staging: none` neste repo):
  - `/backoffice`
  - `/backoffice/activity`
  - `/backoffice/data`
  - `/backoffice/data/:table`
  - `/backoffice/data/:table/:id`
  - `/backoffice/tenants/:tenant_id`
  - `/backoffice/tenants/:tenant_id/activity` (nova)
  - `/backoffice/tenants/:tenant_id/data`
  - `/backoffice/tenants/:tenant_id/data/:table`
  - `/backoffice/tenants/:tenant_id/data/:table/:id`
  - `/backoffice/actions/:action_key/new`
- **Testes:** o tester escreve os testes vermelhos de cada PR a partir dos cenários (só ele edita `test/**`). Os testes que hoje contam `form.lb-reason-form` (`test/integration/reveal_test.rb`) e a lista de rotas não-GET (`test/integration/access_test.rb:147`) são reescritos no PR que muda o comportamento.

## PR 1 — Revelação em lote no modelo e na rota (branch: `feat/panel-layout-1`, base: `main`)

**Entrega:** `Reveal.grant_all(operator:, tenant:, reason:)` e `Reveal.revoke_all(operator:, tenant:)`, mais `POST /reveals` sem `category` e `DELETE /reveals` de coleção. É aditivo: o formulário por categoria e `DELETE /reveals/:id` continuam funcionando.
**Arquivos:** Modify `lib/lucid/backoffice/reveal.rb`, `app/controllers/lucid/backoffice/reveals_controller.rb`, `config/routes.rb`. Test `test/lucid/backoffice/reveal_test.rb`, `test/integration/reveal_test.rb`.
**Detalhe:**
- `grant_all` percorre `configuration.categories - ["public"]`. Para cada categoria, chama `Authorization.allowed?(operator, :reveal, { tenant:, category: })` e pula a negada. Se nenhuma for permitida, levanta `Error::Forbidden`.
- Valida o motivo uma vez, antes de criar qualquer linha (`RecordInvalid` com o erro de `reason`).
- Cria os Reveals e os eventos `backoffice.reveal.grant` numa transação: todos ou nenhum.
- `revoke_all` revoga os Reveals ativos do operador no tenant (`tenant_identifier`), com um evento `backoffice.reveal.revoke` por categoria.
- O controller escolhe `grant_all` quando `params[:category]` está em branco.
- Rotas: `resources :reveals, only: %i[create destroy]` mais `delete "reveals", to: "reveals#destroy_all", as: :reveals_all`.
**Pronto para prod:** a UI atual não muda. As rotas novas existem, mas só a UI do PR 3 as usa.
**Valida:** `bundle exec rake test`

## PR 2 — Layout com sidebar, card de contexto e topbar (branch: `feat/panel-layout-2`, base: `feat/panel-layout-1`)

**Entrega:**
- Layout novo: sidebar com marca, card de contexto, navegação e a seção "Dados" com as tabelas do contexto (`Catalog.tables(tenancy.schema_for(current_tenant))`, sem as `hidden_tables`, só com `allowed?(:browse, tenant:)`).
- Topbar com breadcrumb à esquerda e Sair à direita.
- Gaveta no mobile.
- Rota `tenants/:tenant_id/activity`, com a atividade filtrada pelo tenant e o filtro de tenant escondido no formulário.
- O partial `_reveal_toggle` continua sendo renderizado nas páginas.
**Arquivos:**
- Modify `app/views/layouts/lucid/backoffice/application.html.erb`.
- Create `app/views/lucid/backoffice/shared/_sidebar.html.erb`, `app/views/lucid/backoffice/shared/_context.html.erb`, `app/views/lucid/backoffice/shared/_topbar.html.erb`.
- Modify `app/controllers/lucid/backoffice/application_controller.rb` (helpers `current_context` e `context_tables`), `app/controllers/lucid/backoffice/activity_events_controller.rb` (força `tenant_identifier` quando há `params[:tenant_id]`), `config/routes.rb`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml` (chaves `shared`, `switch_context`, `leave_tenant`, `tenant_overview`, `overview`, `menu`).
- Test: `test/integration/panel_test.rb`, `test/integration/activity_test.rb`.
**Detalhe:**
- A sidebar do contexto compartilhado tem: "Visão geral" (`root_path`, se `allowed?(:view_dashboard)`), "Atividade" (se `allowed?(:view_activity)`), os `lucid_backoffice_menu` e "Dados".
- A sidebar do contexto de tenant tem: "Visão do tenant" (`tenant_path`), "Atividade" (`tenant_activity_path`) e "Dados" (tabelas do tenant).
- O item atual recebe `aria-current="page"`.
- O breadcrumb usa `content_for(:lb_crumbs)`, que cada view preenche no PR 4. Neste PR ele mostra só o contexto.
**Pronto para prod:** as páginas renderizam como antes dentro da nova moldura. A lista de revelação por categoria continua no rodapé. Nenhuma rota some.
**Valida:** `bundle exec rake test`

## PR 3 — Olho de revelação na topbar (branch: `feat/panel-layout-3`, base: `feat/panel-layout-2`)

**Entrega:**
- Olho na topbar, à esquerda do Sair, só para quem tem `allowed?(:reveal, { tenant: current_tenant })`.
- **Mascarado:** ícone de olho riscado com "Dados mascarados". Abre o `<dialog>` com o título "Revelar dados de <contexto>" (sem tenancy: "Revelar dados"), o texto da duração (`reveal_duration` em minutos), as categorias como etiquetas, o campo de motivo com `minlength`, um contador e os botões Cancelar e "Revelar por N min".
- **Ativo:** ícone de olho aberto em destaque com "Revelado até HH:MM" (o menor `expires_at` ativo) e "Encerrar". O `button_to` faz `DELETE reveals_all_path(tenant_id:)`.
**Arquivos:**
- Create `app/views/lucid/backoffice/ui/_reveal_eye.html.erb`.
- Modify `app/views/lucid/backoffice/shared/_topbar.html.erb`, `app/assets/lucid_backoffice.js` (abrir e fechar o `<dialog>` por `data-lb-reveal-open`), `app/assets/lucid_backoffice.css`, `app/controllers/lucid/backoffice/application_controller.rb` (helper `current_reveals`, ativos do operador no contexto), `config/locales/pt-BR.yml`, `config/locales/en.yml` (chaves `reveal_title_in`, `reveal_all`, `revealed_until`, `end_reveal_all`, `masked_data`, `reveal_explainer`, `cancel`).
- Test: `test/integration/reveal_test.rb`.
**Pronto para prod:** o olho funciona sozinho. A lista antiga ainda aparece. As duas convivem por um PR, sem quebra.
**Valida:** `bundle exec rake test`

## PR 4 — Remove a revelação por categoria (branch: `feat/panel-layout-4`, base: `feat/panel-layout-3`)

**Entrega:** some o partial `_reveal_toggle` e os seus três `render`. Somem `@reveals` nos controllers, a rota `DELETE /reveals/:id`, a action `destroy` e o caminho por `category` em `create`. Com isso, `POST /reveals` sempre chama `grant_all`, e um `category` enviado é ignorado.
**Arquivos:**
- Delete `app/views/lucid/backoffice/ui/_reveal_toggle.html.erb`.
- Modify `app/views/lucid/backoffice/records/index.html.erb`, `app/views/lucid/backoffice/records/tables.html.erb`, `app/views/lucid/backoffice/tenants/show.html.erb`, `app/controllers/lucid/backoffice/records_controller.rb`, `app/controllers/lucid/backoffice/tenants_controller.rb`, `app/controllers/lucid/backoffice/reveals_controller.rb`, `config/routes.rb`.
- Test: `test/integration/reveal_test.rb`, `test/integration/access_test.rb`.
**Pronto para prod:** o olho (PR 3) substitui a lista. A suíte de segurança confirma que as rotas não-GET são exatamente `POST /reveals`, `DELETE /reveals` e `POST /actions/:action_key`.
**Valida:** `bundle exec rake test`

## PR 5 — Cabeçalho de página e Ações (branch: `feat/panel-layout-5`, base: `feat/panel-layout-4`)

**Entrega:**
- Novo partial de cabeçalho com breadcrumb, título, subtítulo e ações.
- Ações reescritas:
  - até 3 visíveis viram botões de contorno;
  - acima de 3, a primeira fica como botão e o resto vai num `<details class="lb-menu">` "Ações";
  - a indisponível é `<span class="lb-button" aria-disabled="true">` com estilo tracejado e cinza, e o motivo num `<small>` abaixo, agrupados em `.lb-action`;
  - `danger :high` usa `lb-button-danger`.
- Correção de contraste: `.lb a.lb-button { color: var(--lb-on-accent) }` no primário e `color: var(--lb-text)` no contorno.
**Arquivos:**
- Create `app/views/lucid/backoffice/ui/_page_header.html.erb`.
- Modify `app/views/lucid/backoffice/ui/_actions.html.erb`, `app/views/lucid/backoffice/records/show.html.erb`, `app/views/lucid/backoffice/tenants/show.html.erb`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml` (chave `more_actions`).
- Test: `test/integration/actions_test.rb`, `test/integration/data_test.rb`.
**Detalhe:** `_actions` deixa de ter `<h2>` e seção própria. É chamado de dentro do `_page_header` com `target:`, `record:` e `tenant:`. A página do tenant passa a ter as Ações de `on :tenant` no cabeçalho, e a do registro, as do registro.
**Pronto para prod:** só apresentação. As Ações seguem com as mesmas rotas e permissões.
**Valida:** `bundle exec rake test`

## PR 6 — Listagem, tabelas, painel, atividade e estado vazio no novo padrão (branch: `feat/panel-layout-6`, base: `feat/panel-layout-5`)

**Entrega:**
- `_page_header` em `records/index` (título e contagem, "N registros"), `records/tables`, `dashboard/show` e `activity_events/index`, cada um com `content_for(:lb_crumbs)`.
- Estado vazio: "Nenhum registro em <tabela>".
- No painel, a lista de tenants ganha um botão "Entrar →" por tenant.
- A paginação mostra "1–50 de N".
**Arquivos:**
- Create `app/views/lucid/backoffice/ui/_empty.html.erb`.
- Modify `app/views/lucid/backoffice/records/index.html.erb`, `app/views/lucid/backoffice/records/tables.html.erb`, `app/views/lucid/backoffice/dashboard/show.html.erb`, `app/views/lucid/backoffice/activity_events/index.html.erb`, `app/views/lucid/backoffice/ui/_pager.html.erb`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml`.
- Test: `test/integration/data_test.rb`, `test/integration/panel_test.rb`.
**Pronto para prod:** só apresentação das páginas existentes.
**Valida:** `bundle exec rake test`

## PR 7 — Release 0.3.0 e documentação (branch: `feat/panel-layout-7`, base: `feat/panel-layout-6`)

**Entrega:**
- `VERSION = "0.3.0"`.
- Entrada `## 0.3.0` no `CHANGELOG`, com a seção **Breaking**:
  - `POST /reveals` sem `category` revela tudo;
  - `DELETE /reveals/:id` foi removida em favor de `DELETE /reveals`;
  - o partial `ui/_reveal_toggle` foi removido;
  - as classes `lb-nav`, `lb-reveal` e `lb-reason-form` foram trocadas pela sidebar e pelo olho.
- O `CHANGELOG` também traz uma nota de migração para quem sobrescreve `ui/*` ou usa `config.layout`.
- Docs atualizadas.
- Tag `v0.3.0` após o merge na main.
**Arquivos:** Modify `lib/lucid/backoffice/version.rb`, `CHANGELOG.md`, `docs/masking-and-reveals.md`, `docs/customization.md`, `docs/tenancy.md`, `docs/security.md` (a lista de rotas não-GET), `README.md`.
**Pronto para prod:** só versão e docs.
**Valida:** `bundle exec rake test && git tag --list v0.3.0`

## PR 8 — Luneta adota a 0.3.0 (repo luneta, branch: `chore/backoffice-0-3`, base: `main`)

**Entrega:**
- Gem em `tag: 'v0.3.0'`.
- Saem os 3 `r.menu` duplicados (Escolas, Provisionamentos e Sysadmins), porque as tabelas já estão na sidebar do contexto compartilhado. Os cards ficam.
- Os testes que fazem `POST /backoffice/reveals` com `category` passam a postar sem `category` e checam o Reveal de `documents`.
**Arquivos:**
- Modify `modules/core/code/Gemfile`, `modules/core/code/Gemfile.lock`, `modules/core/code/config/initializers/lucid_backoffice.rb`.
- Test `modules/core/code/test/integration/sysadmin_backoffice_dashboard_test.rb`, `modules/core/code/test/integration/sysadmin_backoffice_access_test.rb`.
- Docs `docs/guides/sysadmin.md`.
**Pronto para prod:** depende só da tag `v0.3.0` publicada.
**Valida:** `make core.test ARGS="test/integration/sysadmin_backoffice_dashboard_test.rb test/integration/sysadmin_backoffice_access_test.rb"` e depois `make core.test`

## SEQUENCE
1. #<pr1> — Revelação em lote no modelo e na rota
2. #<pr2> — Layout com sidebar, card de contexto e topbar
3. #<pr3> — Olho de revelação na topbar
4. #<pr4> — Remove a revelação por categoria
5. #<pr5> — Cabeçalho de página e Ações
6. #<pr6> — Listagem, tabelas, painel, atividade e estado vazio
7. #<pr7> — Release 0.3.0 e documentação
8. #<pr8> — Luneta adota a 0.3.0 (repo luneta, após a tag v0.3.0)
Merge in this order: #<pr1> #<pr2> #<pr3> #<pr4> #<pr5> #<pr6> #<pr7> #<pr8>

# definition of done

- [ ] Todo cenário de "acceptance criteria" foi validado (automatizado ou verificado com comando exato)
- [ ] Testes automáticos passando — suíte verde, não só a parte nova (`bundle exec rake test` na gem; `make core.test` no luneta)
- [ ] Toda task do "how" executada
- [ ] Documentação atualizada (`docs/masking-and-reveals.md`, `docs/customization.md`, `docs/tenancy.md`, `docs/security.md`, `README.md`, `CHANGELOG.md`, `docs/guides/sysadmin.md` do luneta)
- [ ] Staging: `staging: none` (default global, sem seção no `AGENTS.md` da gem nem do luneta) — passo pulado e reportado
- [ ] Cada PR da sequência validado isoladamente (build e testes verdes sem os PRs seguintes)
- [ ] Último PR liga a funcionalidade e remove código temporário (PR 4 remove a revelação por categoria; PR 8 remove os menus duplicados do luneta)
- [ ] Cenário "sidebar mostra o contexto compartilhado por padrão": teste de integração em `test/integration/panel_test.rb`
- [ ] Cenários "entrar no contexto de um tenant" e "sair do tenant volta ao compartilhado": teste de integração com `configure_tenants`
- [ ] Cenário "painel sem tenancy": teste com `config.tenancy = :none` que procura "tenant" (sem diferenciar maiúsculas) no texto visível (`dom.text`) das páginas `/backoffice`, `/backoffice/data` e `/backoffice/data/<tabela>` e não acha, e sem "Trocar"/"Sair do tenant"
- [ ] Cenário "revelar tudo com um motivo": teste de modelo de `Reveal.grant_all` e de integração do `POST /backoffice/reveals` sem `category` (N Reveals e N eventos com o mesmo motivo)
- [ ] Cenários alternativos de motivo curto, categoria negada e nenhuma categoria permitida: testes de `grant_all` (sem linha parcial; 403)
- [ ] Cenário "encerrar tudo pelo olho": teste de `DELETE /backoffice/reveals` (revoga todos, um evento por categoria)
- [ ] Cenário "revelação vale só para o contexto": teste com Reveals em "alfa" checando o olho e a máscara em "beta"
- [ ] Cenário "sem permissão de revelar": teste de que o olho não é renderizado
- [ ] Cenário "lista por categoria não existe mais": teste sem `form.lb-reason-form`/`.lb-reveal` e lista de rotas não-GET exatamente `POST /reveals`, `DELETE /reveals`, `POST /actions/:action_key`
- [ ] Cenário "cabeçalho padrão de página": teste do breadcrumb e das Ações no cabeçalho do registro
- [ ] Cenário "Ações legíveis e indisponíveis de verdade": teste de DOM (`a.lb-button` com texto; indisponível `[aria-disabled=true]` sem `href`, com o motivo em `small`) e regra CSS `.lb a.lb-button` presente em `app/assets/lucid_backoffice.css`
- [ ] Cenário "mais de 3 Ações viram menu": teste de DOM com 4 Ações
- [ ] Cenário "estado vazio": teste de integração com a tabela vazia
- [ ] Cenário "mobile": regra `@media (max-width: 40rem)` para `.lb-sidebar-toggle` presente no CSS, e verificação manual no navegador com a janela estreita (macOS e Linux)
- [ ] Cenário "luneta usa a nova versão": `make core.test` verde no luneta com a gem em `v0.3.0`, e o initializer sem `r.menu`
- [ ] Tag `v0.3.0` publicada no remoto da gem
- [ ] Banner `FINISHED` impresso como última saída (`br4zz4:finish`, Step 7), só com todos os itens acima marcados

## documentation

- `docs/CONTEXT.md` (criado nesta entrevista): contexto, compartilhado, tenant, revelação.
- `docs/masking-and-reveals.md`: `Reveal.grant_all`/`revoke_all`, o olho, as rotas.
- `docs/customization.md`: sidebar, topbar, partials `shared/_sidebar`, `shared/_context`, `shared/_topbar`, `ui/_page_header`, `ui/_reveal_eye`, `ui/_empty`, `configuration.terms[:shared]`.
- `docs/tenancy.md`: contexto compartilhado e contexto de tenant; painel sem tenancy.
- `docs/security.md`: rotas não-GET.
- `CHANGELOG.md`: `0.3.0` com Breaking e migração.
- Luneta `docs/guides/sysadmin.md`: o olho no lugar da lista de categorias.
- `docs/prototypes/PROTOTYPE_panel_layout.html`: removido da main no PR 7 e preservado num branch descartável `prototype/panel-layout` (skill `br4zz4:prototype`).
