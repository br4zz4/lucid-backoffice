---
title: lucid-backoffice v0.1 — painel de operação independente, mascarado por padrão, com trilha de atividade
status: proposed
created: 2026-11-20
updated: 2026-11-20
owner: "@oporpino"
certainty: high
---

# lucid-backoffice v0.1 — painel de operação independente, mascarado por padrão, com trilha de atividade

> **TLDR**: criar a gem `lucid-backoffice` (`br4zz4/lucid-backoffice`, Rails Engine, `Lucid::Backoffice`) que funciona sozinha em qualquer app Rails + PostgreSQL: painel somente leitura com recursos deduzidos do banco e ajustáveis por DSL, toda coluna mascarada por padrão (classificação em YAML versionado), Revelação por categoria com motivo e prazo, trilha de atividade (bloco `track` para qualquer código; automática para `lucid-case` via observer), painel inicial com cards, API de plugin e telas do app dentro do layout, CSS próprio compilado. Autenticação, papéis e permissões vêm do app por configuração; tenancy, `lucid-case` e `active_job` são adaptadores opcionais. Ações corretivas e impersonação ficam na v0.2.

Spec 3 da sequência backoffice. Substitui `docs/specs/20261120200000_lucid_backoffice_gem.md`. Decisões: `docs/adr/0004-own-sysadmin-panel-masked-by-default.md`, `docs/adr/0003-activity-events-synchronous-outbox.md`, `docs/adr/0007-backoffice-as-standalone-gem-with-adapters.md`. Depende das specs `20261120210000_lucid_tenancy_health_api.md` (só para o adaptador de tenancy) e `20261120210100_lucid_case_event_observers.md` (só para a integração `lucid_case`). Esta spec é copiada para `docs/specs/` do repo da gem no PR 1.

# what

Como dev Brazza, quero uma gem de backoffice que eu instale em qualquer app (multi-tenant ou não, com ou sem `lucid-case`, com qualquer autenticação), que mostre os dados sem declarar nada, nunca exponha dado pessoal por omissão, registre quem viu e quem fez o quê, e que eu consiga customizar em camadas até reescrever uma tela inteira, para não reconstruir (nem errar) admin, máscara e trilha em cada projeto e não ficar preso como no Avo.

## out of scope

- Ações corretivas, `editable`, impersonação (spec `20261120210300_lucid_backoffice_actions_impersonation.md`, v0.2).
- Qualquer escrita nos dados do app pelo painel na v0.1 (só Revelação e trilha, em tabelas próprias).
- Login, cadastro de operadores, papéis, 2FA, lockout, rate limit de login: são do app.
- Dependência obrigatória de Devise, CanCanCan, `lucid-tenancy`, `lucid-case` ou Pagy.
- Sentry (plugin `lucid-backoffice-sentry`, spec própria).
- Ações em lote (issue a abrir no repo, ver PR 7).
- Busca textual em coluna mascarada (oráculo). Só `id`, `*_id` e colunas `public`.
- Classificação no banco ou editável pela UI.
- Outros bancos além de PostgreSQL.
- Publicar no RubyGems (consumo por `github:` + `tag:`).

## acceptance criteria

### Integração com o app

    Cenário: sem operador
      Dado a gem montada em "/backoffice" e config.authenticate redirecionando ao login do app
      Quando chega uma requisição sem operador
      Então config.authenticate é chamado e nenhum dado é consultado

    Cenário: padrão negar
      Dado config.authorize não configurado
      Quando um operador abre qualquer tela
      Então recebe 403

    Cenário: autorização por permissão
      Dado config.authorize = ->(op, permission, context) { permission == :browse }
      Quando o operador abre a lista de uma tabela
      Então vê a lista
      E ao tentar revelar recebe 403

    Cenário: configuração inválida no boot
      Dado config.current_operator ausente, ou classification_path inexistente, ou categoria desconhecida no YAML, ou search declarado em coluna não pública
      Quando o app sobe
      Então levanta Lucid::Backoffice::Error::ConfigurationConflict nomeando a chave

    Cenário: sem dependências
      Dado um app sem devise, cancancan, lucid-tenancy, lucid-case e pagy
      Quando instalo a gem e rodo o gerador
      Então o painel sobe e navega os dados

### Dados e máscara

    Cenário: zero declaração
      Dado um app single-tenant com tabelas users e purchases e nenhum recurso declarado
      Quando o operador abre o painel
      Então vê as duas tabelas, com colunas, tipos e associações deduzidos, tudo mascarado exceto as colunas públicas por convenção

    Cenário: tabelas internas e segredos nunca aparecem
      Então schema_migrations, ar_internal_metadata, tabelas da própria gem e config.hidden_tables não aparecem
      E colunas que casam com /password|token|secret|digest|otp|encrypted/ não aparecem nem com Revelação

    Cenário: toda coluna nasce mascarada
      Dado a coluna "cpf" sem entrada no YAML
      Então aparece "•••••" marcada "unclassified"

    Cenário: convenção pública
      Então id, *_id, *_type, created_at e updated_at aparecem em claro sem constar no YAML

    Cenário: máscara por tipo
      Então nulo → "—", texto > 40 caracteres → "[texto, N caracteres]", texto curto → "•••••", data/hora → "••/••/••••", número/booleano → "•••"

    Cenário: ajuste por DSL
      Dado o recurso declarado com column :status, :badge, hide :locale, columns :id, :email, :status, search :id, filter :status, group :customers, label { |r| "Pedido ##{r.id}" }
      Então a lista mostra só id, email (mascarado), status como badge, sem locale, no grupo customers do menu

    Cenário: label não vaza dado
      Dado label { |r| r.email } e email classificado como contact
      Então o label aparece mascarado enquanto não houver Revelação de contact

    Cenário: render e partial próprios
      Dado column :total, render: ->(r) { "R$ #{r.total_cents / 100}" } e total_cents classificado financial
      Então o valor renderizado passa pela máscara de financial
      E um partial app/views/backoffice/purchases/_show_extra.html.erb aparece no detalhe
      E app/views/lucid/backoffice/ui/_table.html.erb do app substitui o da gem

    Cenário: associações
      Então colunas *_id viram link para o registro referenciado e o detalhe lista as associações has_many com contagem e link para a lista filtrada

    Cenário: tabela fora do catálogo
      Quando a URL pede pg_shadow, schema_migrations ou "users;drop"
      Então 404 e nenhum SQL é montado com o nome recebido

    Cenário: filtro e busca sem oráculo
      Quando filtra por id, *_id ou coluna public
      Então filtra
      Quando tenta por coluna mascarada ou valor inválido
      Então o filtro é ignorado com aviso

    Cenário: paginação própria
      Dado 60 registros e page_size 25
      Então 3 páginas, sem ORDER BY por coluna mascarada

### Revelação

    Cenário: revelar categoria
      Dado permissão :reveal e o motivo "investigar chamado 123"
      Quando o operador revela "contact" (no tenant "alfa", se houver tenancy)
      Então contact aparece em claro só para ele, só nesse tenant, por reveal_duration (15 min)
      E as demais categorias e os outros operadores seguem mascarados

    Cenário: motivo obrigatório
      Quando revela sem motivo ou com menos de reveal_reason_min (10) caracteres
      Então nada é revelado e a tela mostra o erro, com o botão desabilitado antes disso

    Cenário: encerrar
      Quando encerra a Revelação
      Então a próxima requisição volta a mascarar

### Tenancy (adaptador)

    Cenário: single-tenant
      Dado config.tenancy = :none
      Então não há lista de tenants e a Revelação vale por operador + categoria

    Cenário: lucid-tenancy
      Dado require "lucid/backoffice/adapters/lucid_tenancy" e config.tenancy = :lucid_tenancy
      Então a raiz lista os tenants com rótulo e estado do schema
      E cada tenant tem navegação por introspecção do seu schema e seção Saúde do schema (Lucid::Tenancy.health)
      E as tabelas compartilhadas aparecem numa área própria

    Cenário: saúde sem ler linhas
      Então a seção Saúde do schema mostra tabelas faltando/sobrando, colunas divergentes e versões pendentes, sem consultar dados de linha

### Trilha de atividade

    Cenário: bloco track
      Dado código sem lucid-case
      Quando executa Lucid::Backoffice::Activity.track("purchases.register") { |a| p = Purchase.create!(...); a.subject(p); result }
      Então há 1 evento "purchases.register", outcome ok, subjects [{type: "Purchase", id:}], changed_fields com nomes sem valores, ator e request do contexto, na mesma transação

    Cenário: track com falha
      Quando o bloco levanta erro
      Então nada é gravado e o erro propaga
      Quando o bloco devolve um resultado com failure? verdadeiro e type :x
      Então o evento é gravado com outcome "x" e a escrita do bloco é desfeita

    Cenário: integração lucid-case automática
      Dado require "lucid/backoffice/integrations/lucid_case"
      Quando Enrollment::Approve (Lucid::Case::Command) termina com sucesso
      Então há 1 evento "enrollment.approve" gravado na transação do Command, sem nada declarado no Command
      E subjects vêm dos records em attributes e no conteúdo do resultado
      E com failure(:last_owner) o evento é gravado depois do rollback com outcome "last_owner"
      E com exceção nada é gravado

    Cenário: payload só com identificadores
      Dado um Command com def activity_payload = { name: "Maria" }
      Então o evento é recusado (falha fechada); valores aceitos: inteiros, nil, booleanos, arrays de inteiros e strings /\A[a-z_.\/]{1,100}\z/

    Cenário: aninhado
      Dado um Command que chama outro
      Então há um evento por Command, com o mesmo request_id, agrupados na tela

    Cenário: falha fechada
      Dado a gravação do evento levantando erro
      Então a escrita do Command ou do bloco é desfeita e o erro propaga

    Cenário: contexto
      Dado o app incluindo Lucid::Backoffice::Context no ApplicationController e config.current_actor
      Então Current tem actor, tenant_identifier, request_id, ip_address, user_agent e reason, zerados ao fim
      E com require "lucid/backoffice/integrations/active_job" o job herda ator e request_id de quem enfileirou; sem ator o evento tem actor_type "System"

    Cenário: o painel registra a si mesmo
      Quando o operador abre uma tabela, um registro, revela ou encerra
      Então eventos backoffice.browse, backoffice.view, backoffice.reveal.grant e backoffice.reveal.revoke com operador, tenant, tabela, categoria e motivo, sem valores
      E se a gravação falha, os dados não são mostrados

    Cenário: evento imutável
      Então um evento persistido não pode ser alterado nem apagado pela API (só pelo expurgo)

    Cenário: expurgo
      Dado eventos com mais de activity_retention (6 meses)
      Quando roda rake lucid:backoffice:purge
      Então são apagados em lotes, os recentes ficam e a contagem é impressa

    Cenário: tela de atividade
      Quando o operador com :view_activity abre a atividade
      Então vê eventos paginados, mais recentes primeiro, agrupados por request_id, filtráveis por tenant, ator, nome e outcome

### Painel, plugins e telas do app

    Cenário: cards do painel inicial
      Dado card :users_total registrado pelo app com value: ->(period) { User.where(created_at: period.range).count }
      Então o painel inicial mostra o card com a alternância Semana/Mês (7/30 dias) e o card some sem a permissão declarada

    Cenário: plugin
      Dado um plugin que registra item de menu, card, seção de tenant e permissão :view_errors
      Então os quatro aparecem para quem tem a permissão

    Cenário: tela do app no layout
      Dado Sysadmin::OrganizationsController < Lucid::Backoffice::ApplicationController e menu "Escolas"
      Então a tela usa layout, autenticação, authorize, Context e kit de UI da gem

    Cenário: CSS e JS próprios
      Dado um app sem Tailwind
      Então o painel é estilizado pelo CSS compilado da gem e a cor de marca vem de config.brand_color
      E o JS da gem (modal de motivo, contagem regressiva) funciona sem Stimulus no app

    Cenário: nada de dado em log, exceção ou URL
      Então valores de coluna não aparecem em logs, mensagens de erro, URLs nem payloads

    Cenário: gerador
      Quando rodo rails g lucid:backoffice:install
      Então são criados initializer comentado, migrations (eventos e Revelações), config/data_classification.yml de exemplo, rota de montagem e exemplo de authorize (CanCanCan e Ruby puro, comentados)

    Cenário: migrations em app com lucid-tenancy
      Dado um app com lucid-tenancy (toda migration precisa declarar onde roda)
      Quando rodo o gerador
      Então as migrations geradas declaram `tenancy :shared` e `db:migrate` as aplica uma vez no schema compartilhado
      E sem lucid-tenancy no app a declaração não é gerada

# why

Luneta e has_warranty precisam do mesmo painel: o has_warranty tem um admin próprio sem máscara e sem trilha, e o luneta ia construir o seu do zero. As regras que importam ("nada nasce visível por omissão", "toda ação deixa rastro", "só escreve por decisão explícita") são as mesmas e só valem se forem testadas num lugar só. Não pode depender das gems da casa nem de Devise para servir a qualquer projeto, e tem de ser customizável em camadas para não repetir a limitação do Avo.

# how

Regras: TDD, minitest + app dummy com PostgreSQL real (padrão `lucid-tenancy`/`lucid-case`; os testes unitários seguem o prefixo `test/lucid/backoffice/` das outras gems, então `test/mask_test.rb` abaixo significa `test/lucid/backoffice/mask_test.rb`; `test/integration/`, `test/generators/` e `test/dummy/` ficam na raiz de `test/`), CI ubuntu (Ruby 3.2 e 3.4) e macOS (3.4), sem comentários explicativos, YARD no público, docs em inglês, i18n `pt-BR`/`en`. Gem: Ruby `>= 3.2`, `railties`/`activerecord` `>= 7.2, < 9`, `pg`. MIT. Semver, `v0.1.0`.

**Feature flag:** não (gem nova).

**Telas da gem** (relativas ao ponto de montagem): `/`, `/tenants/:tenant_id`, `/data`, `/data/:table`, `/data/:table/:id` (com tenancy: `/tenants/:tenant_id/data/...` e `/shared/data/...`), `/reveals` (POST/DELETE), `/activity`.

**Staging:** `staging: none` (gem).

## Desenho

**Configuração** (`Lucid::Backoffice.configure`):
- Integração: `current_operator` (`->(controller) { }`, obrigatório), `authenticate` (`->(controller) { }`, obrigatório), `sign_out_path`, `operator_label` (`->(op) { }`), `current_actor` (`->(controller) { }`, para o `Context` fora do painel), `authorize` (`->(operator, permission, context) { }`, padrão nega).
- Dados: `tenancy` (`:none` padrão, `:lucid_tenancy`, ou objeto do contrato), `classification_path`, `categories` (padrão `public contact documents minors financial free_text unclassified`), `hidden_tables`, `secret_columns` (regex padrão acima), `page_size` (25), `resources_path` (`app/backoffice/resources`).
- Revelação: `reveal_duration` (15 min), `reveal_reason_min` (10).
- Trilha: `activity_retention` (6 meses), `activity_purge_batch` (1000).
- Aparência: `title`, `brand_color`, `layout` (sobrescrever), `terms` (rótulos: "operador", "tenant").

**Permissões** (vocabulário, sem papéis): `:view_dashboard`, `:view_tenant`, `:browse`, `:reveal`, `:view_activity`, mais as registradas por plugins e telas. `context` = `{ tenant:, table:, model:, record:, category: }` quando houver (`model` é a classe AR da tabela, se existir).

**Contrato de tenancy** (`Lucid::Backoffice::Tenancy::Adapter`): `tenants`, `find(identifier)`, `identifier(tenant)`, `label(tenant)`, `with(tenant) { }`, `current`, `shared { }`, `health(tenant)` (opcional; `nil` esconde a seção). Adaptadores: `Null` (single-tenant) e `LucidTenancy` (carregado por `require`, usa só API pública, inclusive `health`).

**Catálogo e recursos:** `Catalog` introspecta as tabelas do escopo (sem tenancy: banco do app; com tenancy: shared + cada tenant) menos internas, da gem, `hidden_tables`. `Resource` (`app/backoffice/resources/*.rb`, `class Purchases < Lucid::Backoffice::Resource`) ajusta uma tabela: `model`/`table`, `group`, `label`, `columns`/`detail` (subconjunto e ordem), `column name, type = nil, render:, partial:`, `hide`, `search`, `filter` (`:period` embutido), `association`, `scope` (`:shared`/`:tenant`). Tipos de exibição: `text`, `datetime`, `date`, `boolean`, `badge`, `money`, `json`, `identifier`, `association`. Sem declaração: deduz do schema e das reflections do model quando a tabela tem model AR. `Records::List`/`Find`: identificadores só do catálogo, `quote_*`, binds, filtro validado, `LIMIT/OFFSET`.

**Classificação e máscara:** `Classification.category_for(table, column)` (convenção → YAML `tabela.coluna: categoria` → `unclassified`), YAML validado no boot. `Mask.call(value:, category:, column_type:, revealed:)`. Todo valor exibido (coluna, `render:`, `label`) passa por `Mask` com a categoria da coluna de origem; `render:`/`label` declaram a coluna de origem (`render: ->(r) { }, from: :total_cents`; `label from: :email`), e sem `from:` o resultado é tratado como `unclassified`.

**Revelação:** tabela `lucid_backoffice_reveals` (`operator_type`, `operator_id`, `tenant_identifier` null, `category`, `reason`, `expires_at`, `revoked_at`, `created_at`); `Reveal.grant`/`revoke`, ativa por `expires_at`/`revoked_at`.

**Trilha:** tabela `lucid_backoffice_activity_events` (shared): `name`, `outcome` (`ok` ou tipo de falha), `actor_type`, `actor_id`, `tenant_identifier`, `subjects` jsonb, `changed_fields` jsonb, `payload` jsonb, `reason`, `request_id`, `ip_address` inet, `user_agent`, `occurred_at`, `created_at`; índices `(tenant_identifier, occurred_at)`, `(actor_type, actor_id, occurred_at)`, `name`, `request_id`, `occurred_at`. `Activity::Event` readonly após persistir, guarda de payload. `Activity.record(...)`, `Activity.track(name, reason: nil) { |activity| }` (`activity.subject(record)`, `activity.payload(hash)`; transação própria ou aninhada; falha se exceção; `outcome` do `type` quando o retorno responde `failure?`). `Current` (`ActiveSupport::CurrentAttributes`). `Context` (concern de controller do app e da engine). Integrações: `lucid/backoffice/integrations/lucid_case` (registra observer em `Lucid::Case.configuration.events.observers`; nome do evento de caso; subjects dos records AR em `attributes` e `result.content`; `changed_fields` de `saved_changes`; `payload` de `activity_payload` se o Command definir) e `lucid/backoffice/integrations/active_job` (serializa `actor` GlobalID e `request_id`). `Activity::Purge` + `rake lucid:backoffice:purge`.

**Extensão:** `Lucid::Backoffice.register(:nome) { |r| r.menu(...); r.card(...); r.tenant_section(...); r.permission(...) }` (plugins e app usam a mesma API). `card key, label:, value: ->(period) { }, permission: :view_dashboard, format: :number`. `Lucid::Backoffice::ApplicationController` público para telas do app.

**UI:** layout escuro com sidebar agrupada e mobile, kit `app/views/lucid/backoffice/ui/` (`_table`, `_stat_card`, `_badge`, `_value`, `_pager`, `_reveal_toggle`, `_reason_modal`, `_flash`), sobrescrevível pelo app. CSS gerado no repo com Tailwind CLI em `app/assets/builds/lucid_backoffice.css` (commitado; CI falha se desatualizado), cor por variável CSS. JS próprio mínimo em `app/assets/javascripts/lucid_backoffice.js` (sem Stimulus/importmap do app).

**Camadas de customização:** (1) nada declarado; (2) DSL do recurso; (3) partials por recurso `app/views/backoffice/<recurso>/{_index,_show,_show_extra}`; (4) componentes `app/views/lucid/backoffice/ui/*`; (5) telas próprias herdando `ApplicationController`.

**Invariantes testados:** padrão negar; falha fechada; nenhum SQL de escrita em tabela do app nas rotas GET (captura de SQL); identificadores só do catálogo; nenhum valor em log/exceção/URL/payload; colunas secretas nunca exibidas; CSRF nas rotas de escrita.

## PR 1 — esqueleto, configuração, classificação e máscara (branch: `feat/lucid-backoffice-1`, base: `main` do repo novo)
**Arquivos:** Create `lucid-backoffice.gemspec`, `Gemfile`, `Rakefile`, `mise.toml`, `.github/workflows/ci.yml`, `lib/lucid/backoffice.rb`, `lib/lucid/backoffice/{version,configuration,errors,classification,mask}.rb`, `test/dummy/` (app Rails mínimo com PostgreSQL), `test/test_helper.rb` — Test `test/configuration_test.rb`, `test/classification_test.rb`, `test/mask_test.rb` — Docs `docs/specs/20261120210200_lucid_backoffice_core.md` (cópia)
**Passos:** testes de configuração inválida, convenção, YAML, `unclassified`, máscara por tipo, colunas secretas → implementação → commit `feat: add configuration, classification and masking`
**Valida:** `bundle exec rake test`

## PR 2 — trilha de atividade (branch: `feat/lucid-backoffice-2`, base: `feat/lucid-backoffice-1`)
**Arquivos:** Create `lib/generators/lucid/backoffice/templates/create_lucid_backoffice_activity_events.rb.tt`, `app/models/lucid/backoffice/activity/event.rb`, `lib/lucid/backoffice/{activity,current,context}.rb`, `lib/lucid/backoffice/activity/{tracker,purge}.rb`, `lib/tasks/lucid_backoffice.rake` — Test `test/activity/event_test.rb`, `test/activity/track_test.rb`, `test/activity/purge_test.rb`, `test/context_test.rb`
**Passos:** testes de track (ok, exceção, failure? com outcome, aninhado, falha fechada), guarda, imutabilidade, contexto, System, expurgo → implementação → commit `feat: add activity trail`
**Valida:** `bundle exec rake test`

## PR 3 — integrações lucid_case e active_job (branch: `feat/lucid-backoffice-3`, base: `feat/lucid-backoffice-2`)
**Arquivos:** Create `lib/lucid/backoffice/integrations/lucid_case.rb`, `lib/lucid/backoffice/integrations/active_job.rb` — Modify `Gemfile` (lucid-case no grupo de teste, versão com observers) — Test `test/integrations/lucid_case_test.rb` (sucesso na transação, failure com outcome após rollback, exceção, activity_payload inválido, aninhado), `test/integrations/active_job_test.rb`
**Passos:** testes → implementação → commit `feat: track lucid-case commands and jobs`
**Valida:** `bundle exec rake test`

## PR 4 — tenancy, catálogo, recursos e leitura (branch: `feat/lucid-backoffice-4`, base: `feat/lucid-backoffice-3`)
**Arquivos:** Create `lib/lucid/backoffice/tenancy/{adapter,null}.rb`, `lib/lucid/backoffice/adapters/lucid_tenancy.rb`, `lib/lucid/backoffice/{catalog,resource}.rb`, `lib/lucid/backoffice/records/{list,find}.rb` — Test `test/catalog_test.rb`, `test/resource_test.rb` (dedução, DSL, `from:`, search em coluna mascarada falha no boot), `test/records_test.rb` (catálogo, filtro, paginação, captura de SQL só leitura), `test/adapters/lucid_tenancy_test.rb` (lucid-tenancy `v0.4.0` no grupo de teste)
**Passos:** testes → implementação → commit `feat: add catalog, resources and tenancy adapters`
**Valida:** `bundle exec rake test`

## PR 5 — Revelação, autorização e eventos do painel (branch: `feat/lucid-backoffice-5`, base: `feat/lucid-backoffice-4`)
**Arquivos:** Create `lib/generators/lucid/backoffice/templates/create_lucid_backoffice_reveals.rb.tt`, `app/models/lucid/backoffice/reveal.rb`, `lib/lucid/backoffice/{authorization,panel_activity}.rb` — Test `test/reveal_test.rb`, `test/authorization_test.rb`, `test/panel_activity_test.rb`
**Passos:** testes (isolamento por operador/tenant/categoria, expiração, motivo, padrão negar, falha fechada do evento do painel) → implementação → commit `feat: add reveals and authorization`
**Valida:** `bundle exec rake test`

## PR 6 — engine, telas, UI, CSS/JS, painel e plugins (branch: `feat/lucid-backoffice-6`, base: `feat/lucid-backoffice-5`)
**Arquivos:** Create `lib/lucid/backoffice/engine.rb`, `lib/lucid/backoffice/registry.rb`, `config/routes.rb`, `app/controllers/lucid/backoffice/{application,dashboard,tenants,records,reveals,activity_events}_controller.rb`, `app/views/layouts/lucid/backoffice/application.html.erb`, `app/views/lucid/backoffice/**` (telas + `ui/*`), `app/assets/{stylesheets/lucid_backoffice.tailwind.css,builds/lucid_backoffice.css,javascripts/lucid_backoffice.js}`, `config/locales/{pt-BR,en}.yml` — Test `test/integration/*_test.rb` (todas as telas, 403, 404, CSRF, cards, plugin, tela do app no layout, override de partial, sem Tailwind no dummy)
**Passos:** testes → implementação → commit `feat: add backoffice engine and screens`
**Valida:** `bundle exec rake test && bundle exec rake assets:check` (task que recompila o CSS e falha se houver diff)

## PR 7 — gerador, helpers de teste, docs e v0.1.0 (branch: `feat/lucid-backoffice-7`, base: `feat/lucid-backoffice-6`)
**Arquivos:** Create `lib/generators/lucid/backoffice/install_generator.rb` e templates (initializer, YAML, rota), `lib/lucid/backoffice/test_helpers.rb`, `README.md`, `docs/{getting-started,configuration,resources,classification,masking-and-reveals,activity,tenancy,plugins,customization,security,testing}.md`, `CHANGELOG.md`, `LICENSE` — Test `test/generators/install_generator_test.rb`, `test/test_helpers_test.rb`
**Passos:** testes → implementação → docs → tag `v0.1.0` → abrir issue no repo com a skill `br4zz4:issue` (urgência baixa): "Bulk actions: apply an action to several selected records (preview per record, one reason, one activity event per record)" → commit `docs: write backoffice documentation`
**Valida:** `bundle exec rake test`

## SEQUENCE
1. #<pr1> — esqueleto, configuração, classificação e máscara
2. #<pr2> — trilha de atividade
3. #<pr3> — integrações lucid_case e active_job
4. #<pr4> — tenancy, catálogo, recursos e leitura
5. #<pr5> — Revelação, autorização e eventos do painel
6. #<pr6> — engine, telas, UI e plugins
7. #<pr7> — gerador, docs e v0.1.0
Merge in this order: #<pr1> #<pr2> #<pr3> #<pr4> #<pr5> #<pr6> #<pr7>

# definition of done

- [ ] Todo cenário de "acceptance criteria" foi validado (automatizado ou verificado com comando exato)
- [ ] Testes automáticos passando — suíte verde, não só a parte nova (CI ubuntu 3.2/3.4 e macOS 3.4)
- [ ] Toda task do "how" executada
- [ ] Documentação atualizada (lista em "documentation")
- [ ] Staging: `staging: none` (gem)
- [ ] Cada PR da sequência validado isoladamente (build e testes verdes sem os PRs seguintes)
- [ ] Último PR liga a funcionalidade e remove código temporário (tag `v0.1.0` publicada)
- [ ] Gemspec sem devise, cancancan, lucid-tenancy, lucid-case, pagy (`grep add_dependency lucid-backoffice.gemspec`)
- [ ] Sem operador → authenticate; sem authorize → 403; authorize por permissão (`test/authorization_test.rb`, integração)
- [ ] Configuração inválida falha no boot (`test/configuration_test.rb`, `test/resource_test.rb`)
- [ ] Zero declaração navega, tabelas internas e colunas secretas ocultas (`test/catalog_test.rb`, integração)
- [ ] Máscara por padrão, convenção, por tipo, em `label`/`render` (`test/mask_test.rb`, `test/resource_test.rb`)
- [ ] DSL, partials por recurso e override de componente (integração)
- [ ] Associações linkadas e contadas (integração)
- [ ] Tabela fora do catálogo → 404 sem SQL; filtro sem oráculo; paginação (`test/records_test.rb`)
- [ ] Revelação: motivo, prazo, isolamento, encerrar (`test/reveal_test.rb`)
- [ ] Single-tenant e lucid-tenancy, saúde sem ler linhas (`test/adapters/lucid_tenancy_test.rb`)
- [ ] track: ok, exceção, failure com outcome, falha fechada, aninhado (`test/activity/track_test.rb`)
- [ ] lucid-case automático, failure após rollback, payload recusado (`test/integrations/lucid_case_test.rb`)
- [ ] Contexto, System e job herdando ator (`test/context_test.rb`, `test/integrations/active_job_test.rb`)
- [ ] Eventos do painel e falha fechada (`test/panel_activity_test.rb`)
- [ ] Evento imutável; expurgo (`test/activity/event_test.rb`, `test/activity/purge_test.rb`)
- [ ] Tela de atividade agrupada e filtrável (integração)
- [ ] Cards, plugin, tela do app no layout (integração)
- [ ] CSS/JS sem Tailwind/Stimulus no app; `assets:check` verde
- [ ] Nada de valor em log/exceção/URL/payload (teste de invariante)
- [ ] Gerador cria initializer, migrations, YAML, rota e exemplos de authorize (`test/generators/install_generator_test.rb`)
- [ ] Com `Lucid::Tenancy` definido, migrations geradas têm `tenancy :shared`; sem, não (`test/generators/install_generator_test.rb`)
- [ ] Issue "Bulk actions" aberta no repo `br4zz4/lucid-backoffice`

## documentation

- Repo da gem: `README.md` e os arquivos de `docs/` listados no PR 7, `CHANGELOG.md`, cópia desta spec.
- Este repo: nenhuma (adoção na spec `20261120210400_luneta_backoffice_adoption.md`).
