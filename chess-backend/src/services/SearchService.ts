import mongoose from 'mongoose';
import { Game } from '../schemas/game';
import { User } from '../schemas/user';

// Model Map for the chess application
const modelMap: { [key: string]: mongoose.Model<any> } = {
    Games: Game,
    Users: User
};

// Dangerous MongoDB operators that could allow code execution or data exfiltration
const DANGEROUS_OPERATORS = new Set([
    '$where', '$function', '$accumulator', '$expr',
    '$merge', '$out', '$collStats', '$indexStats',
    '$planCacheStats', '$currentOp', '$listSessions'
]);

// Allowed aggregation stage operators (whitelist)
const ALLOWED_STAGES = new Set([
    '$match', '$sort', '$project', '$limit', '$skip',
    '$count', '$group', '$unwind', '$lookup',
    '$addFields', '$set', '$facet', '$bucket',
    '$bucketAuto', '$sortByCount', '$replaceRoot'
]);

// Custom Error Classes
class NotFoundError extends Error {
    status: number;
    constructor(message: string) {
        super(message);
        this.name = "NotFoundError";
        this.status = 404;
    }
}

class ValidationError extends Error {
    status: number;
    details: any;
    constructor(message: string, details?: any) {
        super(message);
        this.name = "ValidationError";
        this.status = 400;
        this.details = details;
    }
}

// Helper to get a model
export function getModel(tableName: string) {
    const model = modelMap[tableName];
    if (!model) throw new NotFoundError(`No model found for table: ${tableName}`);
    return model;
}

/**
 * Recursively checks an object for dangerous MongoDB operators.
 * Throws if any are found.
 */
function sanitizeQuery(obj: any, path: string = ''): void {
    if (!obj || typeof obj !== 'object') return;

    if (Array.isArray(obj)) {
        obj.forEach((item, i) => sanitizeQuery(item, `${path}[${i}]`));
        return;
    }

    for (const key of Object.keys(obj)) {
        if (DANGEROUS_OPERATORS.has(key)) {
            throw new ValidationError(`Operator "${key}" is not allowed at ${path}.${key}`);
        }
        if (typeof obj[key] === 'object' && obj[key] !== null) {
            sanitizeQuery(obj[key], `${path}.${key}`);
        }
    }
}

/**
 * Validates that aggregation pipeline stages only use allowed operators.
 */
function validatePipelineStages(pipeline: any[]): void {
    for (const stage of pipeline) {
        const stageKeys = Object.keys(stage);
        for (const key of stageKeys) {
            if (!ALLOWED_STAGES.has(key)) {
                throw new ValidationError(`Aggregation stage "${key}" is not allowed`);
            }
            // Also check for dangerous operators within stage values
            sanitizeQuery(stage[key], key);
        }
    }
}

// Helper function to convert strings to ObjectIds and Dates based on schema
function convertStringsToObjectIdsAndDates(obj: any, schema: mongoose.Schema<any>) {
    if (!obj || typeof obj !== "object") return obj;

    for (const key of Object.keys(obj)) {
        const schemaType = schema.path(key);

        // Handle direct ObjectId fields
        if (
            schemaType &&
            (schemaType.instance === "ObjectID" || schemaType.instance === "ObjectId")
        ) {
            if (typeof obj[key] === "string" && mongoose.Types.ObjectId.isValid(obj[key])) {
                obj[key] = new mongoose.Types.ObjectId(obj[key]);
            }
            if (Array.isArray(obj[key])) {
                obj[key] = obj[key].map((v: any) =>
                    typeof v === "string" && mongoose.Types.ObjectId.isValid(v)
                        ? new mongoose.Types.ObjectId(v)
                        : v
                );
            }
        }
        // Handle arrays of ObjectIds
        else if (
            schemaType &&
            schemaType.instance === "Array" &&
            // @ts-ignore
            schemaType.caster &&
            // @ts-ignore
            (schemaType.caster.instance === "ObjectID" || schemaType.caster.instance === "ObjectId")
        ) {
            if (obj[key] && typeof obj[key] === "object") {
                for (const op of ["$in", "$all", "$nin"]) {
                    if (obj[key][op] && Array.isArray(obj[key][op])) {
                        obj[key][op] = obj[key][op].map((v: any) =>
                            typeof v === "string" && mongoose.Types.ObjectId.isValid(v)
                                ? new mongoose.Types.ObjectId(v)
                                : v
                        );
                    }
                }
            }
        }
        // Handle Date fields
        else if (schemaType && schemaType.instance === "Date") {
            if (typeof obj[key] === "string") {
                obj[key] = new Date(obj[key]);
            }
            if (typeof obj[key] === "object" && obj[key] !== null) {
                for (const op of ["$gte", "$lte", "$gt", "$lt", "$eq", "$ne"]) {
                    if (obj[key][op] && typeof obj[key][op] === "string") {
                        obj[key][op] = new Date(obj[key][op]);
                    }
                }
            }
        }
        // Recursively handle nested objects
        else if (typeof obj[key] === "object" && obj[key] !== null) {
            obj[key] = convertStringsToObjectIdsAndDates(obj[key], schema);
        }
    }
    return obj;
}

const searchService = {
    // Create a new resource
    createResource: async (tableName: string, body: any) => {
        try {
            const Model = getModel(tableName);

            // Block creating Users directly — registration must go through /auth/register
            if (tableName === 'Users') {
                return { success: false, error: 'Cannot create users via this endpoint. Use /auth/register.' };
            }

            const convertedBody = convertStringsToObjectIdsAndDates(body, Model.schema);
            const doc = new Model(convertedBody);
            const result = await doc.save();
            return { success: true, data: result };
        } catch (error: any) {
            if (error.name === "ValidationError") {
                return {
                    success: false,
                    error: "Validation failed",
                    details: error.errors || error.message
                };
            }
            if (error instanceof NotFoundError) {
                return { success: false, error: error.message, status: error.status };
            }
            return { success: false, error: error.message || "Failed to create resource" };
        }
    },

    // Advanced search with aggregation pipeline and pagination
    searchResource: async (
        tableName: string,
        queryBody: any = {},
        options?: { page?: number; pageSize?: number }
    ) => {
        try {
            const Model = getModel(tableName);

            const {
                filter = {},
                sort = { _id: -1 },
                project,
                lookups,
                unwind,
                addFields,
                ...rest
            } = queryBody;

            // Sanitize all user-provided query parts
            sanitizeQuery(filter, 'filter');
            sanitizeQuery(sort, 'sort');
            sanitizeQuery(project, 'project');
            sanitizeQuery(addFields, 'addFields');
            if (Array.isArray(lookups)) sanitizeQuery(lookups, 'lookups');

            const convertedFilter = convertStringsToObjectIdsAndDates({ ...filter }, Model.schema);

            // Pagination with max page size
            const page = options?.page || rest.page || 1;
            const pageSize = Math.min(options?.pageSize || rest.pageSize || 20, 100);
            const skip = (page - 1) * pageSize;

            const pipeline: any[] = [];

            if (convertedFilter && Object.keys(convertedFilter).length > 0) {
                pipeline.push({ $match: convertedFilter });
            }

            if (addFields) {
                pipeline.push({ $addFields: addFields });
            }

            if (Array.isArray(lookups)) {
                for (const lookup of lookups) {
                    pipeline.push({ $lookup: lookup });
                }
            }

            if (unwind) {
                if (Array.isArray(unwind)) {
                    unwind.forEach(u => pipeline.push({ $unwind: u }));
                } else {
                    pipeline.push({ $unwind: unwind });
                }
            }

            if (sort) {
                pipeline.push({ $sort: sort });
            }

            if (project) {
                // Never expose passwordHash
                if (tableName === 'Users') {
                    project.passwordHash = 0;
                }
                pipeline.push({ $project: project });
            } else if (tableName === 'Users') {
                pipeline.push({ $project: { passwordHash: 0 } });
            }

            pipeline.push({
                $facet: {
                    data: [
                        { $skip: skip },
                        { $limit: pageSize }
                    ],
                    total: [
                        { $count: "count" }
                    ]
                }
            });

            const [result] = await Model.aggregate(pipeline);

            const data = result.data;
            const total = result.total.length > 0 ? result.total[0].count : 0;
            const totalPages = Math.ceil(total / pageSize);

            return {
                success: true,
                data,
                pagination: {
                    page,
                    pageSize,
                    total,
                    totalPages
                }
            };
        } catch (error: any) {
            if (error instanceof NotFoundError || error instanceof ValidationError) {
                return { success: false, error: error.message, status: error.status };
            }
            return { success: false, error: error.message || "Failed to search resource" };
        }
    },

    // Get a single resource by ID
    getResource: async (tableName: string, params: any) => {
        try {
            const Model = getModel(tableName);

            const query = params.id ?
                (mongoose.Types.ObjectId.isValid(params.id) ?
                    { _id: params.id } :
                    { id: params.id }) :
                params;

            let q = Model.findOne(query);
            if (tableName === 'Users') {
                q = q.select('-passwordHash');
            }
            const result = await q.lean();

            if (!result) throw new NotFoundError(`Resource not found with id: ${params.id}`);
            return { success: true, data: result };
        } catch (error: any) {
            if (error instanceof NotFoundError) {
                return { success: false, error: error.message, status: error.status };
            }
            return { success: false, error: error.message || "Failed to get resource" };
        }
    },

    // Delete a resource by ID
    deleteResource: async (tableName: string, params: any) => {
        try {
            const Model = getModel(tableName);

            const query = params.id ?
                (mongoose.Types.ObjectId.isValid(params.id) ?
                    { _id: params.id } :
                    { id: params.id }) :
                params;

            const result = await Model.findOneAndDelete(query);
            if (!result) throw new NotFoundError(`Resource not found with id: ${params.id}`);
            return { success: true, data: result };
        } catch (error: any) {
            if (error instanceof NotFoundError) {
                return { success: false, error: error.message, status: error.status };
            }
            return { success: false, error: error.message || "Failed to delete resource" };
        }
    },

    // Update a resource by ID
    updateResource: async (tableName: string, params: any, body: any) => {
        try {
            const Model = getModel(tableName);

            // Block updating sensitive fields directly
            if (tableName === 'Users') {
                delete body.passwordHash;
                delete body.password;
            }

            sanitizeQuery(body, 'body');

            const convertedBody = convertStringsToObjectIdsAndDates(body, Model.schema);

            const query = params.id ?
                (mongoose.Types.ObjectId.isValid(params.id) ?
                    { _id: params.id } :
                    { id: params.id }) :
                params;

            const result = await Model.findOneAndUpdate(
                query,
                { $set: convertedBody },
                { new: true, runValidators: true }
            );

            if (!result) throw new NotFoundError(`Resource not found with id: ${params.id}`);
            return { success: true, data: result };
        } catch (error: any) {
            if (error.name === "ValidationError") {
                return {
                    success: false,
                    error: "Validation failed",
                    details: error.errors || error.message
                };
            }
            if (error instanceof NotFoundError || error instanceof ValidationError) {
                return { success: false, error: error.message, status: (error as any).status };
            }
            return { success: false, error: error.message || "Failed to update resource" };
        }
    },

    // Direct aggregation pipeline execution
    directAggregation: async (tableName: string, pipelineBody: any[]) => {
        try {
            const Model = getModel(tableName);

            // Validate pipeline stages against whitelist
            validatePipelineStages(pipelineBody);

            // Process each pipeline stage to convert string ObjectIds to real ObjectIds
            const processedPipeline = pipelineBody.map(stage => {
                const processedStage: any = {};
                for (const [key, value] of Object.entries(stage)) {
                    processedStage[key] = convertStringsToObjectIdsAndDates(value, Model.schema);
                }
                return processedStage;
            });

            // Always exclude passwordHash from Users queries
            if (tableName === 'Users') {
                processedPipeline.push({ $project: { passwordHash: 0 } });
            }

            const result = await Model.aggregate(processedPipeline);

            return {
                success: true,
                data: result
            };
        } catch (error: any) {
            if (error instanceof NotFoundError || error instanceof ValidationError) {
                return { success: false, error: error.message, status: (error as any).status };
            }
            return {
                success: false,
                error: error.message || "Failed to execute direct aggregation"
            };
        }
    }
};

export default searchService;
