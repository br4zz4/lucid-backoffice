---
title: Gerenciar dados no painel — busca, filtros, relacionamentos, campos travados e criar/editar/excluir declarados
status: proposed
created: 2026-11-24
updated: 2026-11-24
owner: "@oporpino"
certainty: high
---

# Gerenciar dados no painel — busca, filtros, relacionamentos, campos travados e criar/editar/excluir declarados

> **TLDR**: o operador passa a buscar, filtrar e ordenar pelas **colunas visíveis**: públicas sempre, mascaradas só com revelação ativa e com o critério guardado no servidor (ADR 0001). Também navega por chaves estrangeiras e por "Relacionados", e cria, edita ou exclui registros nas tabelas que o app declarar (`creatable`, `editable`, `destroyable`), sempre como Ação: motivo, prévia, permissão e evento. Campos de colunas mascaradas aparecem travados com bolinhas até a revelação, o que fecha o vazamento atual do `initial_values`. Entrega a gem 0.4.0 e exemplos no luneta (`users` e `classrooms`).

Spec 2 de 2. Depende de `20261124100000_panel_layout_and_reveal_eye.md` (sidebar, cabeçalho de página, Ações no cabeçalho, olho). Decisões: `docs/adr/0001-search-revealed-columns-server-side.md` (gem) e ADR 0004 do luneta (`~/workspace/brazza.tech/lunetamagica/docs/adr/0004-own-sysadmin-panel-masked-by-default.md`), que segue valendo para escrita: só Ações curadas, agora também derivadas de declaração. Glossário: `docs/CONTEXT.md`.

# what

Como operador do painel, quero achar registros por busca e filtros, navegar entre registros relacionados e criar, editar ou excluir registros nas tabelas que o app liberou, sempre com motivo e rastro, para operar o dia a dia sem pedir mudança no banco a um dev.

## out of scope

- CRUD genérico em tabela não declarada: tabela sem `creatable`, `editable` ou `destroyable` continua só leitura (ADR 0004).
- Ações em lote (bulk) e importação/exportação CSV.
- Busca em coluna mascarada sem revelação ativa, e qualquer critério em coluna oculta (`secret` ou `hide`).
- Associações polimórficas (`*_type` + `*_id`) como link: aparecem como valor simples.
- Menus de plugin por contexto de tenant (issue separada, aberta na Spec A).
- Feature flag: não há (ver `# how`).

## acceptance criteria

    Cenário: buscar por coluna pública
      Dado a tabela "users" com a coluna pública "role"
      Quando o operador filtra "role = teacher"
      Então a lista mostra só usuários com role "teacher"
      E a URL contém "filter[role]=teacher"

    Cenário: coluna mascarada não é filtrável sem revelação
      Dado a coluna "email" de categoria "contact" e nenhuma revelação ativa
      Quando o operador abre "+ Filtro"
      Então "email" não aparece entre as colunas filtráveis
      E "GET ...?filter[email]=x" ignora o critério e mostra o aviso de filtro ignorado

    Cenário: coluna revelada fica pesquisável, com o critério no servidor
      Dado o operador com revelação ativa no contexto
      Quando ele busca "maria" em "users"
      Então a lista mostra os usuários cujo name ou email contém "maria" (sem diferenciar maiúsculas)
      E a URL contém só "q=<token>" e nenhum trecho de "maria"
      E o evento "backoffice.browse" registra as colunas usadas e não o texto buscado

    Cenário alternativo: revelação acaba com o filtro aplicado
      Dado uma lista aberta com "?q=<token>" que filtra por "email"
      Quando a revelação expira ou é encerrada
      E o operador recarrega a página
      Então o critério de "email" é ignorado e a página avisa "Filtro em coluna mascarada ignorado: email"

    Cenário alternativo: coluna oculta nunca é critério
      Dado a coluna "encrypted_password" em hide e a coluna "api_token" de categoria "secret"
      Quando o operador envia um critério por qualquer uma delas, com ou sem revelação
      Então o critério é ignorado e nenhum SQL com essas colunas no WHERE ou no ORDER BY é executado

    Cenário: ordenar por coluna visível
      Quando o operador clica no cabeçalho "created_at"
      Então a lista é ordenada por created_at crescente, e um segundo clique inverte
      E colunas mascaradas não reveladas não têm link de ordenação

    Cenário: link de chave estrangeira
      Dado "classrooms.grade_id" com foreign key para "grades"
      Quando o operador abre a lista de "classrooms"
      Então o valor de grade_id é um link para o registro de "grades" no mesmo contexto

    Cenário: Relacionados
      Dado o usuário 42 referenciado por 3 linhas de "enrollments.user_id"
      Quando o operador abre o registro 42 de "users"
      Então o card "Relacionados" mostra "enrollments 3" com link para a lista de enrollments filtrada por user_id = 42

    Cenário: criar um registro declarado
      Dado um Resource com "creatable :name, :email, :role" e o operador com a permissão create_record
      Quando o operador clica em "Novo registro" na lista de "users", preenche os campos, a prévia e o motivo
      Então o registro é criado pelo model (ou pelo Command de with:)
      E um evento "backoffice.action.create_users" é gravado com o motivo
      E o operador vai para a página do registro criado

    Cenário alternativo: criar falha por validação
      Quando o model ou o Command recusa os dados
      Então nada é gravado, o formulário volta com a mensagem de erro e os campos preenchidos

    Cenário alternativo: tabela não declarada
      Dado a tabela "messages" sem Resource com creatable
      Quando o operador abre a lista
      Então não há "Novo registro"
      E "GET /backoffice/actions/create_messages/new" responde 404

    Cenário alternativo: sem permissão
      Dado um operador sem create_record
      Quando ele abre a lista de "users"
      Então "Novo registro" não aparece e o POST da ação responde 403

    Cenário: campo travado na edição
      Dado "editable :name, :email" em "users", "email" de categoria "contact" e nenhuma revelação ativa
      Quando o operador abre "Editar" no usuário 42
      Então "name" é um input com o valor atual
      E "email" é um campo desabilitado com "•••••" e o aviso "Revele os dados para editar"
      E o HTML da página não contém o e-mail do usuário

    Cenário: campo destrava com a revelação
      Dado o operador com revelação ativa no contexto
      Quando ele abre "Editar" no usuário 42
      Então "email" é um input com o e-mail atual

    Cenário alternativo: campo travado enviado à força
      Dado "email" travado
      Quando um POST da ação envia fields[email]=outro@x.com
      Então o valor enviado é descartado e o email do registro não muda

    Cenário alternativo: Command recebe o valor atual do campo travado
      Dado "editable ..., with: Organization::Update" com "cnpj" travado
      Quando o operador salva a edição de outros campos
      Então o Command recebe cnpj com o valor atual do registro (lido no servidor), e o cnpj não vira nil

    Cenário: excluir um registro declarado
      Dado "destroyable" em "classrooms" e o operador com destroy_record
      Quando ele escolhe "Excluir registro" no menu de Ações, digita o id para confirmar e informa o motivo
      Então o registro é excluído, um evento "backoffice.action.destroy_classrooms" é gravado e o operador volta à lista

    Cenário alternativo: exclusão recusada pelo model
      Dado uma classroom com enrollments (dependent: :restrict_with_error)
      Quando o operador tenta excluí-la
      Então nada é excluído e a mensagem de erro do model aparece

    Cenário: exemplos no luneta
      Dado o luneta com lucid-backoffice v0.4.0
      Quando um superadmin entra no contexto de uma escola
      Então em "users" ele pode criar (convite com e-mail de definição de senha) e editar (email travado até revelar)
      E em "classrooms" ele pode criar, editar o turno e excluir
      E um sysadmin "support" não vê nenhuma dessas ações

# why

O painel hoje só lê e só filtra por id na URL. Na prática:
- **Achar alguém:** o operador precisa paginar ou montar a URL na mão.
- **Navegar:** não dá para seguir `classroom_id` até a turma.
- **Criar dados:** é impossível ("não consigo adicionar um dado"), e para isso alguém abre um console Rails em produção, sem motivo nem rastro. É exatamente o risco que o ADR 0004 quis tirar.
- **DSL sem uso:** o `Resource` já declara `search`, `filter` e `association`, mas nada disso é usado em lugar nenhum.
- **Vazamento:** `Action#initial_values` põe no formulário o valor atual de colunas mascaradas, em claro (`lib/lucid/backoffice/action.rb:142`). Num `editable :cnpj` (o luneta tem `Resources::Organizations`), o operador vê o CNPJ sem ter revelado nada.

# how

Repos:
- **gem**: `~/workspace/br4zz4/lucid-backoffice`. Suíte: `bundle exec rake test`.
- **luneta**: `~/workspace/brazza.tech/lunetamagica`, app em `modules/core/code`. Suíte: `make core.test`.

Decisões de implementação:
- **Feature flag:** não há. As capacidades são aditivas e opt-in por declaração: busca e filtro só aparecem para colunas visíveis, e criar/editar/excluir só para tabelas declaradas. O campo travado é uma correção de segurança e entra sem flag.
- **Coluna utilizável** (para buscar, filtrar ou ordenar): pertence a `Records.visible` e não é oculta, e a categoria é `public` ou está em `Reveal.categories_for(operator:, tenant:)`. Uma regra só, em `Records::Query#usable?(column, revealed)`, usada pelo SQL e pela UI.
- **Critério na URL x no servidor** (ADR 0001):
  - `filter[col]=v` e `sort=col`/`dir=asc|desc` na URL só valem para colunas `public`, `id` e `*_id`.
  - Busca textual e critérios em coluna revelada vão por `POST .../data/:table/query`. O controller grava `session[:lb_queries][token] = { "table", "tenant", "filters", "search", "sort", "dir" }`, com token `SecureRandom.urlsafe_base64(12)` e no máximo 20 entradas, descartando as mais antigas. Depois redireciona para `?q=token`.
  - Token de outra tabela ou de outro contexto é ignorado.
  - O cookie de sessão do Rails é criptografado. Nenhum valor vai para a URL nem para o log; o `browse` registra só os nomes das colunas.
- **SQL:**
  - igualdade com bind para filtro;
  - `ILIKE` com `sanitize_sql_like` e bind para busca, sobre `CAST(col AS text)` nas colunas buscáveis que forem utilizáveis;
  - `ORDER BY` só por coluna utilizável e com `quote_column_name`, mais `id` como desempate.
  - Identificadores vêm só do catálogo, como hoje.
- **Colunas buscáveis:** as do `Resource.search`; sem declaração, todas as colunas de texto utilizáveis. `Resource.search` deixa de exigir `public` e passa a recusar só coluna oculta (`ConfigurationConflict`). `Resource.filter` define os filtros sugeridos no "+ Filtro"; sem declaração, todas as colunas utilizáveis aparecem.
- **Relacionamentos:** a ordem de resolução é:
  1. foreign keys do banco (`connection.foreign_keys("schema.tabela")`);
  2. `Resource.association`;
  3. convenção `x_id` → `x.pluralize`, se a tabela existir no catálogo do mesmo schema.
  "Relacionados" mostra as tabelas que apontam para a atual (foreign keys do banco mais `association` declaradas em outros Resources), no máximo 20, com `COUNT(*)` por bind.
- **Ação de registro:** `creatable`, `editable` e `destroyable` geram subclasses de `Action`, como o `editable` já faz.

  | DSL | key | alvo | permissão | label | perform padrão | depois |
  |---|---|---|---|---|---|---|
  | `creatable *cols, with:` | `create_<tabela>` | coleção da tabela | `:create_record` | "Novo registro" | `model.create!(values)` | vai para o registro criado |
  | `editable *cols, with:` | `edit_<tabela>` | registro | `:update_record` (antes `:run_action`) | "Editar" | `record.update!(values)` | volta ao registro |
  | `destroyable with:` | `destroy_<tabela>` | registro, `danger :high` | `:destroy_record` | "Excluir registro" | `record.destroy!` | vai para a lista |

  - `with: Command` passa os campos como atributos (mais `record` e `tenant`, quando declarados), como hoje.
  - O model sai de `tabela.classify.safe_constantize`. Sem model ActiveRecord, levanta `ConfigurationConflict` no boot.
  - Erros de validação (`ActiveRecord::RecordInvalid`, `RecordNotDestroyed`) viram `result` de falha com `errors.full_messages.to_sentence`.
- **Alvo de coleção:** `Action.on(:users, collection: true)` e `Action.collection?`. `ActionsController#find_record` devolve `nil` para ação de coleção. A lista renderiza as Ações de coleção no cabeçalho (a primeira é o botão primário), e o registro, as de registro.
- **Campo travado:**
  - `Action#initial_values` e o form recebem `revealed:`.
  - Um campo com o nome de uma coluna do alvo cuja categoria não é `public` nem está revelada vira `Action::Field::LOCKED`, sentinela que o form desenha como `<input disabled value="•••••">` com cadeado e o aviso, sem `name`, então nunca é enviado.
  - Na execução (`Runner`), um valor recebido para campo travado é descartado. O valor atual do registro é lido no servidor e passado ao `perform` e ao Command, para que nada vire `nil`.
  - Em ação de coleção, que não tem registro, nada trava.
  - A prévia continua mascarada como hoje.
- **Telas criadas ou editadas:**
  - `/backoffice/data/:table` e `/backoffice/tenants/:tenant_id/data/:table` (busca, filtros, ordenação, "Novo registro");
  - `/backoffice/data/:table/:id` e `/backoffice/tenants/:tenant_id/data/:table/:id` (links, Relacionados, Editar, Excluir);
  - `/backoffice/actions/:action_key/new` (campos travados).
  - `staging: none` nos dois repos.
- **Testes:** o tester escreve os testes vermelhos de cada PR a partir dos cenários. A suíte de segurança ganha a rota não-GET `POST .../data/:table/query` e um teste de captura de SQL: nenhuma coluna oculta e nenhuma coluna mascarada não revelada no `WHERE` ou no `ORDER BY`.

## PR 1 — Campos travados nas Ações (branch: `feat/record-management-1`, base: `main` com a Spec A mergeada)

**Entrega:** a sentinela `LOCKED`. `initial_values(revealed:)` não devolve valor de coluna mascarada. O form desenha o campo travado. O `Runner` descarta o valor enviado para campo travado e injeta o valor atual lido no servidor. O controller passa `Reveal.categories_for`.
**Arquivos:** Modify `lib/lucid/backoffice/action.rb`, `lib/lucid/backoffice/action/field.rb`, `lib/lucid/backoffice/action/runner.rb`, `app/controllers/lucid/backoffice/actions_controller.rb`, `app/views/lucid/backoffice/actions/_field.html.erb`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml` (chave `locked_field`). Test `test/lucid/backoffice/action/field_test.rb`, `test/lucid/backoffice/action/runner_test.rb`, `test/integration/editable_test.rb`, `test/integration/actions_test.rb`.
**Pronto para prod:** fecha um vazamento. Ações sem campos mascarados não mudam.
**Valida:** `bundle exec rake test`

## PR 2 — Consulta: filtro, busca e ordenação por colunas utilizáveis (branch: `feat/record-management-2`, base: `feat/record-management-1`)

**Entrega:** `Records::Query` (`filters`, `search`, `sort`, `dir`, `usable?`, `ignored`) e `Records.list(query:, revealed:)`, com o SQL descrito acima. `Resource.search` aceita coluna não oculta. Sem UI ainda: o `index` passa uma `Query` montada só de `filter[...]` com as regras novas.
**Arquivos:** Create `lib/lucid/backoffice/records/query.rb`. Modify `lib/lucid/backoffice/records.rb`, `lib/lucid/backoffice/resource.rb`, `app/controllers/lucid/backoffice/records_controller.rb`. Test `test/lucid/backoffice/records_test.rb`, `test/lucid/backoffice/resource_test.rb`.
**Pronto para prod:** os filtros por `id` e `*_id` continuam iguais. Colunas públicas passam a valer na URL, e nada mascarado é aplicado sem revelação.
**Valida:** `bundle exec rake test`

## PR 3 — Barra de consulta na listagem e critério no servidor (branch: `feat/record-management-3`, base: `feat/record-management-2`)

**Entrega:**
- Barra acima da tabela: campo de busca, chips dos filtros ativos (com ✕) e "+ Filtro" em `<details>` (select de colunas utilizáveis e um valor).
- Cabeçalhos ordenáveis.
- `POST data/:table/query` e `POST tenants/:tenant_id/data/:table/query` gravando na sessão e redirecionando com `q`.
- Aviso de critério ignorado.
- `PanelActivity.browse` com `criteria: [nomes de coluna]`.
**Arquivos:** Create `app/views/lucid/backoffice/ui/_query_bar.html.erb`. Modify `config/routes.rb`, `app/controllers/lucid/backoffice/records_controller.rb`, `app/views/lucid/backoffice/records/index.html.erb`, `app/views/lucid/backoffice/ui/_table.html.erb`, `lib/lucid/backoffice/panel_activity.rb`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml`. Test `test/integration/data_test.rb`, `test/integration/access_test.rb`, `test/lucid/backoffice/panel_activity_test.rb`.
**Pronto para prod:** a consulta é só leitura. A rota nova tem CSRF e entra na lista de rotas não-GET.
**Valida:** `bundle exec rake test`

## PR 4 — Links de chave estrangeira e Relacionados (branch: `feat/record-management-4`, base: `feat/record-management-3`)

**Entrega:**
- `Catalog.references(schema, table)` (ida) e `Catalog.referenced_by(schema, table)` (volta), na ordem de resolução descrita acima.
- `Records::Cell` ganha `link` (tabela e id) para coluna de chave estrangeira, renderizado em `ui/_value` no contexto atual.
- Card "Relacionados" no registro, com contagens.
**Arquivos:** Create `app/views/lucid/backoffice/ui/_related.html.erb`. Modify `lib/lucid/backoffice/catalog.rb`, `lib/lucid/backoffice/records.rb`, `app/controllers/lucid/backoffice/records_controller.rb`, `app/views/lucid/backoffice/ui/_value.html.erb`, `app/views/lucid/backoffice/records/show.html.erb`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml`. Test `test/lucid/backoffice/catalog_test.rb`, `test/lucid/backoffice/records_test.rb`, `test/integration/data_test.rb`.
**Pronto para prod:** só leitura, aditivo.
**Valida:** `bundle exec rake test`

## PR 5 — `creatable`, `destroyable`, alvo de coleção e permissões de registro (branch: `feat/record-management-5`, base: `feat/record-management-4`)

**Entrega:**
- `Action.on(table, collection: true)`.
- `Resource.creatable` e `Resource.destroyable`.
- `editable` passa a usar `:update_record`.
- Redirecionamentos pós-execução: criar vai para o registro criado, excluir vai para a lista.
- Erros de validação viram falha legível.
- Ações de coleção no cabeçalho da lista.
**Arquivos:** Modify `lib/lucid/backoffice/action.rb`, `lib/lucid/backoffice/action/runner.rb`, `lib/lucid/backoffice/resource.rb`, `app/controllers/lucid/backoffice/actions_controller.rb`, `app/views/lucid/backoffice/ui/_actions.html.erb`, `app/views/lucid/backoffice/records/index.html.erb`, `config/locales/pt-BR.yml`, `config/locales/en.yml` (chaves `new_record`, `destroy_record`, `edit`). Test `test/lucid/backoffice/resource_test.rb`, `test/lucid/backoffice/action/dsl_test.rb`, `test/integration/editable_test.rb`, `test/integration/actions_test.rb`.
**Pronto para prod:** nenhuma tabela ganha escrita sem declarar. Quem já usa `editable` precisa conceder `:update_record` (quebra anotada no `CHANGELOG`).
**Valida:** `bundle exec rake test`

## PR 6 — Release 0.4.0 e documentação (branch: `feat/record-management-6`, base: `feat/record-management-5`)

**Entrega:**
- `VERSION = "0.4.0"`.
- `CHANGELOG` `## 0.4.0`, com a seção **Breaking**: `editable` exige `:update_record`; `search` aceita coluna não pública; `Records.list` recebe `query:`.
- Docs atualizadas.
- Nota no ADR 0004 do luneta apontando para o ADR 0001 da gem.
- Tag `v0.4.0` após o merge.
**Arquivos:** Modify `lib/lucid/backoffice/version.rb`, `CHANGELOG.md`, `docs/resources.md`, `docs/actions.md`, `docs/security.md`, `docs/masking-and-reveals.md`, `README.md`. Luneta: `docs/adr/0004-own-sysadmin-panel-masked-by-default.md` (linha "Narrowed by lucid-backoffice ADR 0001: revealed columns are searchable"), num commit próprio no repo do luneta, dentro do PR 7.
**Pronto para prod:** só versão e docs.
**Valida:** `bundle exec rake test && git tag --list v0.4.0`

## PR 7 — Luneta: exemplos em users e classrooms (repo luneta, branch: `feat/backoffice-record-actions`, base: `main` com o PR 8 da Spec A mergeado)

**Entrega:**
- Gem em `tag: 'v0.4.0'`.
- **`users`** (contexto de escola), exemplo com `with:`:
  - `creatable :name, :email, :role, with: User::Invite`. `User::Invite` é um Command novo, com `attributes :name, :email, :role`: cria o `User` com `password: Devise.friendly_token(32)` e chama `User::SendPasswordReset.call(user:)`, para que a pessoa defina a própria senha. Falha de validação vira `failure(:invalid, errors:)`.
  - `editable :name, :email, :role`, no padrão sem `with:`, para mostrar o campo travado: `email` é `contact`.
- **`classrooms`**, exemplo do padrão sem Command: Resource novo `Resources::Classrooms` com `creatable :grade_id, :shift_id`, `editable :shift_id` e `destroyable`. A exclusão é recusada pelo `restrict_with_error` quando há matrículas.
- `SysadminAbility` sem mudança: o superadmin já tem tudo, e o `support` não recebe `create_record`, `update_record` nem `destroy_record`. Um teste garante isso.
**Arquivos:**
- Modify `modules/core/code/Gemfile`, `modules/core/code/Gemfile.lock`, `modules/core/code/app/backoffice/resources/users.rb`.
- Create `modules/core/code/app/backoffice/resources/classrooms.rb`, `modules/core/code/app/core/cases/user/invite.rb`.
- Test `modules/core/code/test/core/cases/user/invite_test.rb`, `modules/core/code/test/backoffice/resources/record_actions_test.rb`.
- Docs `docs/guides/sysadmin.md` e `docs/adr/0004-own-sysadmin-panel-masked-by-default.md`.
**Pronto para prod:** depende só da tag `v0.4.0`. `Resources::Organizations` já usa `editable ... with: Organization::Update` e passa a ter os campos de documentos travados até revelar.
**Valida:** `make core.test ARGS="test/core/cases/user/invite_test.rb test/backoffice/resources/record_actions_test.rb"` e depois `make core.test`

## SEQUENCE
1. #<pr1> — Campos travados nas Ações
2. #<pr2> — Consulta: filtro, busca e ordenação por colunas utilizáveis
3. #<pr3> — Barra de consulta na listagem e critério no servidor
4. #<pr4> — Links de chave estrangeira e Relacionados
5. #<pr5> — creatable, destroyable, alvo de coleção e permissões
6. #<pr6> — Release 0.4.0 e documentação
7. #<pr7> — Luneta: exemplos em users e classrooms (após a tag v0.4.0)
Merge in this order: #<pr1> #<pr2> #<pr3> #<pr4> #<pr5> #<pr6> #<pr7>

# definition of done

- [ ] Todo cenário de "acceptance criteria" foi validado (automatizado ou verificado com comando exato)
- [ ] Testes automáticos passando — suíte verde, não só a parte nova (`bundle exec rake test` na gem; `make core.test` no luneta)
- [ ] Toda task do "how" executada
- [ ] Documentação atualizada (`docs/resources.md`, `docs/actions.md`, `docs/security.md`, `docs/masking-and-reveals.md`, `README.md`, `CHANGELOG.md`; luneta `docs/guides/sysadmin.md` e nota no ADR 0004)
- [ ] Staging: `staging: none` nos dois repos — passo pulado e reportado
- [ ] Cada PR da sequência validado isoladamente (build e testes verdes sem os PRs seguintes)
- [ ] Último PR liga a funcionalidade e remove código temporário (PR 7 declara as tabelas no luneta; nenhum código temporário na gem)
- [ ] Cenário "buscar por coluna pública": teste de integração com `filter[role]` na URL
- [ ] Cenário "coluna mascarada não é filtrável sem revelação": teste de `Records::Query#usable?` e de integração (fora do select, critério ignorado com aviso)
- [ ] Cenário "coluna revelada fica pesquisável": teste de integração do `POST .../query` → redirect com `q`, URL sem o texto buscado, evento `browse` com nomes de coluna e sem o valor
- [ ] Cenário "revelação acaba com o filtro aplicado": teste com o Reveal revogado e o mesmo `q`
- [ ] Cenário "coluna oculta nunca é critério": teste de captura de SQL (`ActiveSupport::Notifications` `sql.active_record`) sem a coluna oculta nem a mascarada não revelada em `WHERE`/`ORDER BY`
- [ ] Cenário "ordenar por coluna visível": teste de integração da ordem e da ausência de link nas mascaradas
- [ ] Cenário "link de chave estrangeira": teste de `Catalog.references` com FK real no banco de teste e de DOM
- [ ] Cenário "Relacionados": teste de `Catalog.referenced_by` e da contagem e do link filtrado
- [ ] Cenários de criar (sucesso, validação, tabela não declarada, sem permissão): testes de `Resource.creatable` e de integração (registro criado, evento com motivo, redirect; 404; 403)
- [ ] Cenários de campo travado (travado, destrava, enviado à força, Command recebe o valor atual): testes de `initial_values`, do `Runner` e de integração (HTML sem o valor mascarado)
- [ ] Cenários de excluir (sucesso e recusa do model): testes de `Resource.destroyable` com `danger :high` e falha legível
- [ ] Cenário "exemplos no luneta": `make core.test` verde com os testes de `User::Invite` e de `record_actions_test.rb` (superadmin vê as ações, support não)
- [ ] Tag `v0.4.0` publicada no remoto da gem
- [ ] Banner `FINISHED` impresso como última saída (`br4zz4:finish`, Step 7), só com todos os itens acima marcados

## documentation

- `docs/adr/0001-search-revealed-columns-server-side.md` (criado nesta entrevista).
- `docs/CONTEXT.md`: coluna visível, coluna oculta, campo travado, ação de registro (criado nesta entrevista).
- `docs/resources.md`: `search` (coluna não oculta), `filter`, `association`, `creatable`, `editable` (`:update_record`), `destroyable`.
- `docs/actions.md`: alvo de coleção, campos travados, permissões de registro.
- `docs/security.md`: critérios no servidor, rota `query`, regra de coluna utilizável.
- `docs/masking-and-reveals.md`: o que a revelação libera (leitura, busca e edição).
- `CHANGELOG.md`: `0.4.0` com Breaking.
- Luneta: `docs/guides/sysadmin.md` (criar usuário por convite, turmas) e nota no ADR 0004.
