import { Elysia, t } from 'elysia';
import searchService from '../services/SearchService';

export const searchRoutes = new Elysia({ prefix: '/search' })
    // POST /search/:tableName - Advanced search with aggregation
    .post('/searchresource/:tableName', async ({ params, body, query }) => {
        const { tableName } = params;
        const options = {
            page: query.page ? parseInt(query.page as string) : undefined,
            pageSize: query.pageSize ? parseInt(query.pageSize as string) : undefined
        };

        return await searchService.searchResource(tableName, body, options);
    }, {
        params: t.Object({
            tableName: t.String()
        }),
        query: t.Optional(t.Object({
            page: t.Optional(t.String()),
            pageSize: t.Optional(t.String())
        })),
        body: t.Optional(t.Object({
            filter: t.Optional(t.Any()),
            sort: t.Optional(t.Any()),
            project: t.Optional(t.Any()),
            lookups: t.Optional(t.Array(t.Any())),
            unwind: t.Optional(t.Union([t.String(), t.Array(t.String())])),
            addFields: t.Optional(t.Any()),
            customStages: t.Optional(t.Array(t.Any()))
        }))
    })

    // GET /search/:tableName/:id - Get single resource
    .get('/searchresource/:tableName/:id', async ({ params }) => {
        const { tableName, id } = params;
        return await searchService.getResource(tableName, { id });
    }, {
        params: t.Object({
            tableName: t.String(),
            id: t.String()
        })
    })

    // POST /search/:tableName/create - Create new resource
    .post('/createresource/:tableName', async ({ params, body }) => {
        const { tableName } = params;
        return await searchService.createResource(tableName, body);
    }, {
        params: t.Object({
            tableName: t.String()
        }),
        body: t.Any()
    })

    // PUT /search/:tableName/:id - Update resource
    .put('/updateresource/:tableName/:id', async ({ params, body }) => {
        const { tableName, id } = params;
        return await searchService.updateResource(tableName, { id }, body);
    }, {
        params: t.Object({
            tableName: t.String(),
            id: t.String()
        }),
        body: t.Any()
    })

    // PATCH /search/:tableName/:id - Update resource (alternative method)
    .patch('/updateresource/:tableName/:id', async ({ params, body }) => {
        const { tableName, id } = params;
        console.log("PATCH update body", body, params);
        try {
            const result = await searchService.updateResource(tableName, { id }, body);
            return result;
        } catch (error: any) {
            console.error("PATCH update error:", error);
            return { success: false, error: error.message || "Failed to update resource" };
        }
    }, {
        params: t.Object({
            tableName: t.String(),
            id: t.String()
        }),
        body: t.Any()
    })

    // DELETE /search/:tableName/:id - Delete resource
    .delete('/deleteresource/:tableName/:id', async ({ params }) => {
        const { tableName, id } = params;
        return await searchService.deleteResource(tableName, { id });
    }, {
        params: t.Object({
            tableName: t.String(),
            id: t.String()
        })
    })

    // POST /search/:tableName/aggregate - Direct aggregation
    .post('/aggregatetable/:tableName', async ({ params, body }) => {
        const { tableName } = params;
        return await searchService.directAggregation(tableName, body);
    }, {
        params: t.Object({
            tableName: t.String()
        }),
        body: t.Array(t.Any())
    });
