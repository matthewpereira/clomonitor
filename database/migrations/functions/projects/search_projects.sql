-- Search for projects using the input parameters provided and returns the
-- results in json format.
create or replace function search_projects(p_input jsonb)
returns table(projects json, total_count bigint) as $$
declare
    v_limit int := coalesce((p_input->>'limit')::int, 20);
    v_offset int := coalesce((p_input->>'offset')::int, 0);
    v_sort_by text := coalesce(p_input->>'sort_by', 'name');
    v_sort_direction text := coalesce(p_input->>'sort_direction', 'asc');
    v_text text := (p_input->>'text');
    v_foundation text[];
    v_maturity text[];
    v_rating text[];
    v_passing_check text[];
    v_not_passing_check text[];
    v_accepted_from date := (p_input->>'accepted_from');
    v_accepted_to date := (p_input->>'accepted_to');
begin
    -- Prepare filters
    if p_input ? 'foundation' and p_input->'foundation' <> 'null' then
        select array_agg(e::text) into v_foundation
        from jsonb_array_elements_text(p_input->'foundation') e;
    end if;
    if p_input ? 'maturity' and p_input->'maturity' <> 'null' then
        select array_agg(e::text) into v_maturity
        from jsonb_array_elements_text(p_input->'maturity') e;
    end if;
    if p_input ? 'rating' and p_input->'rating' <> 'null' then
        select array_agg(e::text) into v_rating
        from jsonb_array_elements_text(p_input->'rating') e;
    end if;
    if p_input ? 'passing_check' and p_input->'passing_check' <> 'null' then
        select array_agg(e::text) into v_passing_check
        from jsonb_array_elements_text(p_input->'passing_check') e;
    end if;
    if p_input ? 'not_passing_check' and p_input->'not_passing_check' <> 'null' then
        select array_agg(e::text) into v_not_passing_check
        from jsonb_array_elements_text(p_input->'not_passing_check') e;
    end if;

    return query
    with filtered_projects as (
        select
            p.project_id,
            p.name,
            p.display_name,
            p.description,
            p.category,
            p.home_url,
            p.logo_url,
            p.devstats_url,
            p.score,
            p.rating,
            p.passed_checks,
            p.accepted_at,
            p.updated_at,
            p.maturity,
            p.foundation_id
        from project p
        where score is not null
        and
            case when v_text is not null then
                (p.name ~* v_text or p.display_name ~* v_text) else true
            end
        and
            case when cardinality(v_foundation) > 0 then
            p.foundation_id = any(v_foundation) else true end
        and
            case when cardinality(v_maturity) > 0 then
            p.maturity::text = any(v_maturity) else true end
        and
            case when cardinality(v_rating) > 0 then
            p.rating = any(v_rating) else true end
        and
            case when v_accepted_from is not null then
            p.accepted_at >= v_accepted_from else true end
        and
            case when v_accepted_to is not null then
            p.accepted_at <= v_accepted_to else true end
        and
            case when cardinality(v_passing_check) > 0 then
            passed_checks @> v_passing_check else true end
        and
            case when cardinality(v_not_passing_check) > 0 then
            not passed_checks && v_not_passing_check else true end
    )
    select
        (
            select coalesce(json_agg(json_strip_nulls(json_build_object(
                'id', project_id,
                'name', name,
                'display_name', display_name,
                'description', description,
                'category', category,
                'home_url', home_url,
                'logo_url', logo_url,
                'devstats_url', devstats_url,
                'score', score,
                'rating', rating,
                'accepted_at', extract(epoch from accepted_at),
                'updated_at', floor(extract(epoch from updated_at)),
                'maturity', maturity,
                'repositories', (
                    select json_agg(json_build_object(
                        'name', r.name,
                        'url', r.url,
                        'check_sets', r.check_sets,
                        'website_url', rp.data->'documentation'->'website'->'url'
                    ))
                    from repository r
                    left join report rp using (repository_id)
                    where project_id = fp.project_id
                ),
                'foundation', foundation_id
            ))), '[]')
            from (
                select *
                from filtered_projects
                order by
                    (case when v_sort_by = 'score' and v_sort_direction = 'asc' then (score->>'global')::real end) asc,
                    (case when v_sort_by = 'score' and v_sort_direction = 'desc' then (score->>'global')::real end) desc,
                    (case when v_sort_by = 'name' and v_sort_direction = 'asc' then name end) asc,
                    (case when v_sort_by = 'name' and v_sort_direction = 'desc' then name end) desc
                limit v_limit
                offset v_offset
            ) fp
        ),
        (
            select count(*) from filtered_projects
        );
end
$$ language plpgsql;
